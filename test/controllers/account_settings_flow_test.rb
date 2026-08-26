require "test_helper"

class AccountSettingsFlowTest < ActionDispatch::IntegrationTest
  test "signed-in user changes their own password end to end" do
    user = users(:juan)
    sign_in user

    get edit_user_registration_path
    assert_response :success
    assert_select "h2", "Cambiar mi contraseña"

    put user_registration_path, params: {
      user: { current_password: "password123", password: "newpassword123", password_confirmation: "newpassword123" }
    }
    assert_redirected_to root_path

    delete destroy_user_session_path
    post user_session_path, params: { user: { email: user.email, password: "newpassword123" } }
    assert_redirected_to root_path
  end

  test "changing the password requires the correct current password" do
    user = users(:juan)
    sign_in user

    put user_registration_path, params: {
      user: { current_password: "wrongpassword", password: "newpassword123", password_confirmation: "newpassword123" }
    }
    assert_response :unprocessable_entity

    delete destroy_user_session_path
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
    assert_redirected_to root_path
  end

  test "account settings page never offers self sign-up" do
    get new_user_session_path
    assert_response :success
    assert_no_match(/Regístrate/, response.body)
  end
end
