class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("SMTP_FROM", "no-reply@nalakalu.com")
  layout "mailer"
end
