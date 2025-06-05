require "./spec_helper"

describe Mail::Client do
  # Some specs send actual emails, so we guard those behind the SEND_TEST_EMAIL
  # env var. If you want to send real emails as part of your tests, set the
  # following env vars (or add them to a .env file):
  #
  # SEND_TEST_EMAIL=true
  # SMTP_SERVER=smtp.example.com
  # SMTP_DOMAIN=your-domain.tld
  # SMTP_LOGIN=user
  # SMTP_PASSWORD=secret
  # TEST_EMAIL_FROM_NAME="Example Sender"
  # TEST_EMAIL_FROM_ADDRESS="sender@example.com"
  # TEST_EMAIL_TO_NAME="Your Name Here"
  # TEST_EMAIL_TO_ADDRESS="you@example.com"
  # TEST_EMAIL_SUBJECT="..."
  # TEST_EMAIL_ATTACHMENT_PATH=/path/to/attachment
  # TEST_EMAIL_ATTACHMENT_CONTENT_TYPE=image/png
  #
  # NOTE: This does not guarantee delivery. This test only validates that your
  # SMTP server does not reject the email.
  if ENV["SEND_TEST_EMAIL"]?
    mail = Mail::Client.new ENV["SMTP_SERVER"], 587,
      domain: ENV["SMTP_DOMAIN"],
      auth: Mail::Auth::Login.new(id: ENV["SMTP_LOGIN"], password: ENV["SMTP_PASSWORD"])

    it "sends an email" do
      # Log.setup :trace, backend: Log::IOBackend.new(STDOUT)

      file = File.new ENV["ATTACHMENT_PATH"]
      mail.send Mail::Message.new(
        from: Mail::Message::Party.new(
          name: ENV["TEST_EMAIL_FROM_NAME"],
          address: ENV["TEST_EMAIL_FROM_ADDRESS"],
        ),
        to: [
          Mail::Message::Party.new(
            name: ENV["TEST_EMAIL_TO_NAME"],
            address: ENV["TEST_EMAIL_TO_ADDRESS"],
          ),
        ],
        subject: ENV["TEST_EMAIL_SUBJECT"],
        parts: [
          Mail::Message::Part.text("This is a test email sent from an integration test in the https://github.com/jgaskins/mail Crystal shard."),
          Mail::Message::Part.attachment(
            filename: File.basename(ENV["ATTACHMENT_PATH"]),
            content_type: ENV["ATTACHMENT_CONTENT_TYPE"],
            body: file,
          ),
        ],
      )
    end
  end
end
