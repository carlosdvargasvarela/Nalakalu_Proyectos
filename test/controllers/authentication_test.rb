require "test_helper"

class AuthenticationTest < ActionDispatch::IntegrationTest
  test "anonymous visitor is redirected to sign in" do
    get root_path
    assert_redirected_to new_user_session_path
  end

  test "signed in user can reach the projects index" do
    sign_in users(:juan)
    get root_path
    assert_response :success
  end
end
