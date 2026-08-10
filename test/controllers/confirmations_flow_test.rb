require "test_helper"

class ConfirmationsFlowTest < ActionDispatch::IntegrationTest
  test "unconfirmed user must confirm before signing in" do
    user = perform_enqueued_jobs { User.create!(email: "nuevo@example.com", password: "password123", password_confirmation: "password123", role: "visor") }
    assert_not user.confirmed?

    post user_session_path, params: { user: { email: user.email, password: "password123" } }
    assert_redirected_to new_user_session_path
    follow_redirect!
    assert_select ".alert", /confirmar tu correo/

    mail = ActionMailer::Base.deliveries.find { |m| m.to == [user.email] && m.subject == "Instrucciones de confirmación" }
    token = mail.html_part.body.to_s[/confirmation_token=([^"&]+)/, 1]
    assert token.present?

    get user_confirmation_path(confirmation_token: token)
    assert_redirected_to new_user_session_path

    assert user.reload.confirmed?

    post user_session_path, params: { user: { email: user.email, password: "password123" } }
    assert_redirected_to root_path
  end

  test "resend confirmation form renders and re-sends the email" do
    user = User.create!(email: "otro@example.com", password: "password123", password_confirmation: "password123", role: "visor")

    get new_user_confirmation_path
    assert_response :success
    assert_select "h2", "Reenviar confirmación"

    assert_emails 1 do
      post user_confirmation_path, params: { user: { email: user.email } }
    end
  end
end
