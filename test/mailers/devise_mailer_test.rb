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

  test "password_change notifies with no CTA link" do
    mail = Devise::Mailer.password_change(@user)
    assert_equal "Contraseña modificada", mail.subject
    body = mail.html_part.body.to_s
    assert_match @user.email, body
    assert_no_match "href=", body
  end

  test "email_changed notifies about a pending reconfirmation" do
    # reconfirmable's postpone-and-set-unconfirmed_email logic is a before_save
    # callback, so it only runs on save/update, not on a bare assignment.
    @user.update!(email: "nuevo@example.com")
    mail = Devise::Mailer.email_changed(@user)
    assert_equal "Correo electrónico modificado", mail.subject
    body = mail.html_part.body.to_s
    assert_match "nuevo@example.com", body
  end
end
