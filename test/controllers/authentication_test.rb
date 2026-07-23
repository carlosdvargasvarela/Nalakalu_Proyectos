require "test_helper"

class AuthenticationTest < ActionDispatch::IntegrationTest
  test "anonymous visitor is redirected to sign in" do
    get root_path
    assert_redirected_to new_user_session_path
  end

  test "anonymous visitor cannot reach admin" do
    get admin_project_types_path
    assert_redirected_to new_user_session_path
  end

  test "signed in user can reach the projects index" do
    sign_in users(:juan)
    get root_path
    assert_response :success
  end

  test "sign-in page is in Spanish" do
    get new_user_session_path
    assert_response :success
    assert_select "h2", "Iniciar sesión"
    assert_select "input[value=?]", "Iniciar sesión"
  end

  test "sign-up page is in Spanish" do
    get new_user_registration_path
    assert_response :success
    assert_select "h2", "Registrarse"
    assert_select "input[value=?]", "Registrarse"
  end
end
