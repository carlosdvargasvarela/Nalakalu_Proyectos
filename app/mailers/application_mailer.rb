class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("SMTP_USERNAME", "no-reply@nalakalu.com")
  layout "mailer"
end
