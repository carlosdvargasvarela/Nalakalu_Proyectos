require "test_helper"

class DeviseMailerTest < ActionMailer::TestCase
  setup { @user = users(:juan) }

  test "confirmation_instructions renders the branded layout" do
    mail = Devise::Mailer.confirmation_instructions(@user, "faketoken")
    body = mail.html_part&.body&.to_s || mail.body.to_s
    assert_match "Nalakalu", body
  end

  test "confirmation_instructions has the confirmation link and CTA label" do
    mail = Devise::Mailer.confirmation_instructions(@user, "faketoken")
    assert_equal "Instrucciones de confirmación", mail.subject
    assert_equal [@user.email], mail.to
    body = mail.html_part.body.to_s
    assert_match "Confirmar mi cuenta", body
    assert_match "confirmation_token=faketoken", body
    assert_match "faketoken", mail.text_part.body.to_s
  end

  test "reset_password_instructions has the reset link and CTA label" do
    mail = Devise::Mailer.reset_password_instructions(@user, "faketoken")
    assert_equal "Instrucciones para restablecer tu contraseña", mail.subject
    body = mail.html_part.body.to_s
    assert_match "Cambiar mi contraseña", body
    assert_match "reset_password_token=faketoken", body
    assert_match "faketoken", mail.text_part.body.to_s
  end
end
