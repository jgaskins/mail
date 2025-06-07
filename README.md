# Mail

Crystal shard that sends email over SMTP.

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     mail:
       github: jgaskins/mail
   ```

2. Run `shards install`

## Usage

```crystal
require "mail"
```

Instantiate the mail client. This can be a constant or in your application's config:

```crystal
# src/config/mail.cr

# Using a constant
MAIL = Mail::Client.new ENV["SMTP_SERVER"], 587,
  domain: ENV["SMTP_DOMAIN"],
  auth: Mail::Auth::Login.new(ENV["SMTP_LOGIN"], ENV["SMTP_PASSWORD"])

# Using some kind of application-level configuration
Config.define mail : Mail::Client = Mail::Client.new ENV["SMTP_SERVER"], 587,
  domain: ENV["SMTP_DOMAIN"],
  auth: Mail::Auth::Login.new(ENV["SMTP_LOGIN"], ENV["SMTP_PASSWORD"])
```

Then you can send messages:

```crystal
MAIL.send Mail::Message.new(
  from: "me@example.com",
  to: ["you@example.com"],
  subject: "Howdy",
  parts: [
    Mail::Message::Part.text("Hey there!"),
  ],
)
```

Note that `to`, `cc`, and `bcc` are arrays, even when there is a single recipient. You do not have to specify `cc` or `bcc` if there aren't any.

### Personalizing sender and recipients

The sending party and all receiving parties (`to`, `cc`, and `bcc`) can either be `String`s or `Mail::Party` instances. The purpose of a `Mail::Party` is to provide both a human-readable name for the mail client to display as well as an email address.

```crystal
MAIL.send Mail::Message.new(
  from: Mail::Party.new(name: "Admin", address: "admin@example.com"),
  to: [
    Mail::Party.new(name: "Example User", address: "user@example.com"),
  ],
  # ...
)
```

On mail clients, this will display the sender as `Admin` and the recipient as `Example User`.

### Sending HTML with Text fallback

Some email clients don't support HTML emails, so you can provide both HTML and text versions of the email:

```crystal
MAIL.send Mail::Message.new(
  # ...
  parts: [
    Mail::Message::Part.html(html_content),
    Mail::Message::Part.text(text_content),
  ],
)
```

### Attachments

You can also attach files to messages:

```crystal
File.open(filename) do |file|
  MAIL.send Mail::Message.new(
    # ...
    parts: [
      Mail::Message::Part.html("Please see the attached file"),
      Mail::Message::Part.attachment(
        filename: File.basename(filename),
        content_type: "image/jpg",
        body: file,
      ),
    ],
  )
end
```

The file will be streamed to the SMTP server and will not be loaded all into memory at once.

## Contributing

1. Fork it (<https://github.com/jgaskins/mail/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Jamie Gaskins](https://github.com/jgaskins) - creator and maintainer
