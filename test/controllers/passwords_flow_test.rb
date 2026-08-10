require "test_helper"

class PasswordsFlowTest < ActionDispatch::IntegrationTest
  test "user resets their password end to end" do
    user = users(:juan)

    get new_user_password_path
    assert_response :success
    assert_select "h2", "Recuperar contraseña"

    assert_emails 1 do
      post user_password_path, params: { user: { email: user.email } }
    end

    mail = ActionMailer::Base.deliveries.last
    token = mail.html_part.body.to_s[/reset_password_token=([^"&]+)/, 1]
    assert token.present?

    get edit_user_password_path(reset_password_token: token)
    assert_response :success

    put user_password_path, params: {
      user: { reset_password_token: token, password: "newpassword123", password_confirmation: "newpassword123" }
    }
    assert_redirected_to root_path

    delete destroy_user_session_path

    post user_session_path, params: { user: { email: user.email, password: "newpassword123" } }
    assert_redirected_to root_path
  end
end
