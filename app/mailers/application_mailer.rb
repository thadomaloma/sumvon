class ApplicationMailer < ActionMailer::Base
  default from: -> { ENV.fetch("MAILER_FROM", "Sumvon <no-reply@localhost>") }
  layout "mailer"
end
