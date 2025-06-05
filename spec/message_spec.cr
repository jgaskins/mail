require "./spec_helper"

describe Mail::Message do
  it "encodes headers" do
    message = create_message(
      to: [
        Mail::Message::Party.new(
          name: "Doe, John",
          address: "john@example.com",
        ),
        %{"O'Brien, Mary" <mary@example.com>},
      ],
    )

    message.to_header.should eq %{To: "Doe, John" <john@example.com>,\r\n "O'Brien, Mary" <mary@example.com>\r\n}
  end

  it "encodes headers with non-ASCII names" do
    message = create_message(
      to: [Mail::Message::Party.new(name: "山田太郎", address: "yamada@example.jp")],
    )

    message.to_header.should eq %{To: =?UTF-8?B?5bGx55Sw5aSq6YOO?= <yamada@example.jp>\r\n}
  end

  it "does not encode a cc header if there is no cc on the message" do
    message = create_message(cc: nil)

    message.cc_header.should eq ""
  end

  it "encodes a cc header if there is a cc on the message" do
    message = create_message(
      cc: [
        Mail::Message::Party.new(
          name: "Doe, John",
          address: "john@example.com",
        ),
        %{"O'Brien, Mary" <mary@example.com>},
      ],
    )

    message.cc_header.should eq %{Cc: "Doe, John" <john@example.com>,\r\n "O'Brien, Mary" <mary@example.com>\r\n}
  end
end

private def create_message(
  from sender : Mail::Message::EncodableParty = "me@example.com",
  to = %w[you@example.com],
  cc = nil,
  bcc = nil,
  subject : String = "",
  parts : Array(Mail::Message::Part) = [] of Mail::Message::Part,
) : Mail::Message
  Mail::Message.new(
    from: sender,
    to: to,
    cc: cc,
    bcc: bcc,
    subject: subject,
    parts: parts,
  )
end
