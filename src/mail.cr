require "http/headers"
require "log"
require "db/pool"
require "socket"
require "openssl"
require "base64"
require "mime-extensions"
require "mime/multipart"

# TODO: Write documentation for `Mail`
module Mail
  VERSION = "0.1.0"

  Log = ::Log.for("mail")

  class Error < ::Exception
  end

  class Client
    getter host : String
    getter port : Int32
    getter domain : String
    getter tls : TLS
    getter auth : Auth::Method

    def initialize(
      @host,
      @port,
      *,
      @domain,
      @tls = :starttls,
      @auth,
      @log = Mail::Log,
    )
      @connections = DB::Pool(SMTP::Connection).new do
        SMTP::Connection.new host, port,
          tls: tls,
          domain: domain,
          auth: auth,
          log: log
      end
    end

    def send(message : Message) : Nil
      # Retry in the case of a long-lived socket getting disconnected.
      retry 3 { send! message }
    end

    private def send!(message : Message) : Nil
      @connections.checkout do |smtp|
        smtp.mail_from address_for(message.from)
        unless (response = smtp.read_response).starts_with? "250"
          raise SMTP::Error.new("Unexpected response from MAIL FROM:")
        end
        success = true
        {message.to, message.cc?, message.bcc?}.each do |recipient_list|
          recipient_list.try &.each do |recipient|
            smtp.rcpt_to address_for(recipient)
            success = false unless (response = smtp.read_response).starts_with? '2'
          end
        end
        unless success
          raise SMTP::Error.new("Unexpected response from RCPT TO: #{response}")
        end

        smtp.data do |io|
          MIME::Multipart.build io do |mime|
            message.from_header io
            message.to_header io
            message.cc_header io
            # We don't add BCC headers. There should be no evidence in the
            # message of who is in BCC.
            io.puts "Subject: #{message.subject}"
            io.puts "Content-Type: #{mime.content_type}"
            io.puts

            message.parts.each do |part|
              mime.body_part part.headers do |io|
                part.encode io
              end
            end
          end
        end
      rescue ex
        smtp.close
        raise ex
      end
    end

    private def retry(times : Int, &)
      error = nil
      times.times do
        return yield
      rescue ex : IO::Error
        error = ex
      end

      # If we get here, we've definitely encountered at least one error
      raise error.not_nil!
    end

    private def address_for(recipient : String)
      recipient
    end

    private def address_for(recipient : Message::Party)
      recipient.address
    end
  end

  module SMTP
    class Connection
      getter host : String
      getter port : Int32
      getter domain : String
      getter tls : TLS
      getter auth : Auth::Method
      getter log : ::Log
      private getter socket : TCPSocket | OpenSSL::SSL::Socket::Client

      private CRLF = "\r\n"

      def initialize(
        @host,
        @port,
        *,
        @domain,
        @tls,
        @auth,
        @log,
      )
        log.trace &.emit "Connecting", host: host, port: port, domain: domain
        @socket = TCPSocket.new(host, port)
        if tls.smtps?
          @socket = OpenSSL::SSL::Socket::Client.new @socket, sync_close: true
        end
        send "EHLO #{domain}"
        capabilities = read_multiline_response

        if tls.starttls?
          send "STARTTLS"
          read_response

          @socket = OpenSSL::SSL::Socket::Client.new @socket,
            sync_close: true,
            hostname: host
          send "EHLO #{domain}"
          capabilities = read_multiline_response
        end

        if auth
          auth.authenticate self
        end
      end

      def mail_from(sender : String)
        send "MAIL FROM:<#{sender}>"
      end

      def rcpt_to(recipient : String)
        send "RCPT TO:<#{recipient}>"
      end

      def data(&)
        send "DATA"
        unless (response = read_response).starts_with? "354"
          raise SMTP::Error.new("Unexpected response from DATA: #{response}")
        end
        yield Data.new(@socket)
        @socket << "\r\n.\r\n"
        @socket.flush
        @log.trace &.emit "Sent data"
        unless (response = read_response).starts_with? '2'
          raise SMTP::Error.new("Unexpected response from DATA: #{response}")
        end
      end

      def quit
        send "QUIT"
        read_response
      end

      def close
        @socket.close
      end

      class Data < IO
        @io : IO

        def initialize(@io)
        end

        def read(slice : Bytes)
          raise NotImplementedError.new("Cannot read from a write-only SMTP DATA block.")
        end

        def write(slice : Bytes) : Nil
          @io.write slice
        end
      end

      protected def send(command : String) : Nil
        @log.trace &.emit ">>>", command: command
        @socket.puts command
        @socket.flush
      end

      protected def read_multiline_response : Array(String)
        responses = [read_response] of String
        loop do
          response = read_response
          responses << response
          break unless response[3] == '-'
        end
        responses
      end

      protected def read_response : String
        response = socket.read_line
        @log.trace &.emit "<<<", command: response

        code = response[0...3].to_i
        raise SMTP::Error.new(response) if code >= 400

        response
      end
    end

    class Error < Mail::Error
    end
  end

  enum TLS
    None
    STARTTLS
    SMTPS
  end

  struct Message
    getter from : EncodableParty
    getter to : Parties
    getter cc : Parties { [] of String }
    getter bcc : Parties { [] of String }
    getter subject : String?
    getter parts : Array(Part)

    def initialize(
      *,
      @from,
      @to,
      @cc = nil,
      @bcc = nil,
      @subject,
      @parts,
    )
    end

    private macro define_header_method(*headers)
      {% for header in headers %}
        def {{header.id.underscore}}_header : String
          String.build { |str| {{header.id.underscore}}_header str }
        end
      {% end %}
    end

    define_header_method from, to, cc

    def from_header(io : IO) : Nil
      io << "From: " << from << "\r\n"
    end

    def to_header(io : IO) : Nil
      io << "To: "
      to.each_with_index 1 do |recipient, index|
        if index > 1
          io << ' '
        end

        io << recipient

        if index < to.size
          io << ','
        end

        io << "\r\n"
      end
    end

    def cc_header(io : IO) : Nil
      if cc = cc?
        io << "Cc: "
        cc.each_with_index 1 do |recipient, index|
          if index > 1
            io << ' '
          end

          io << recipient

          if index < cc.size
            io << ','
          end

          io << "\r\n"
        end
      end
    end

    def cc?
      @cc
    end

    def bcc?
      @bcc
    end

    struct Part
      getter headers : Headers
      getter body : Body

      alias Body = IO | String

      def self.text(body)
        new :text, body
      end

      def self.html(body)
        new :html, body
      end

      def self.attachment(filename : String, body : IO, content_type : String)
        new(
          headers: HTTP::Headers{
            "Content-Type"              => content_type,
            "Content-Transfer-Encoding" => "base64",
            "Content-Disposition"       => %{attachment; filename="#{filename.gsub('"', "\\\"")}"},
          },
          body: body,
        )
      end

      def self.new(type : Type, body : Body)
        new(
          headers: Headers{
            "Content-Type"              => type.to_header,
            "Content-Transfer-Encoding" => type.encoding,
          },
          body: body,
        )
      end

      def initialize(@headers, @body)
      end

      def encode(io : IO) : Nil
        case encoding
        in .quoted_printable?
          body.each_line do |line|
            if line == "."
              line = ".."
            end

            io << MIME::QuotedPrintable.encode(line) << "\r\n"
          end
        in .base64?
          body = self.body
          body = IO::Memory.new(body) if body.is_a? String
          MIME::Base64.encode body, io
        end
      end

      def encoding
        case encoding = headers["Content-Transfer-Encoding"]?
        when "quoted-printable"
          Encoding::QuotedPrintable
        when "base64"
          Encoding::Base64
        else
          raise Error.new(%{Unknown Content-Transfer-Encoding: #{encoding.inspect}. Only "quoted-printable" and "base64" are supported.})
        end
      end

      enum Type
        HTML
        Text
        Attachment

        def to_header
          case self
          in .html?
            "text/html"
          in .text?
            "text/plain"
          in .attachment?
            "application/octet-stream"
          end
        end

        def encoding
          case self
          in .html?, .text?
            "quoted-printable"
          in .attachment?
            "base64"
          end
        end
      end

      enum Encoding
        QuotedPrintable
        Base64
      end
    end

    record Party, name : String, address : String do
      def to_s(io : IO) : Nil
        if name.ascii_only?
          name.inspect io
        else
          io << "=?UTF-8?B?"
          Base64.strict_encode name, io
          io << "?="
        end

        io << " <" << address << '>'
      end
    end

    alias EncodableParty = String | Party
    alias Parties = Array(String) | Array(Party) | Array(EncodableParty)
  end

  alias Headers = HTTP::Headers
  alias Party = Message::Party

  module Auth
    abstract struct Method
      abstract def authenticate(smtp : SMTP::Connection)
    end

    record Login < Method, id : String, password : String do
      def authenticate(smtp : SMTP::Connection)
        smtp.send "AUTH LOGIN"
        unless (response = smtp.read_response).starts_with? "334"
          raise SMTP::Error.new("Unexpected SMTP AUTH LOGIN response: #{response}")
        end

        smtp.send Base64.strict_encode(id)
        unless (response = smtp.read_response).starts_with? "334"
          raise SMTP::Error.new("Unexpected SMTP response to username: #{response}")
        end

        smtp.send Base64.strict_encode(password)
        unless (response = smtp.read_response).starts_with? "235"
          raise SMTP::Error.new("Could not log into SMTP: #{response}")
        end
      end
    end
  end
end
