require "test_helper"

class UserPreferencesFlowTest < ActionDispatch::IntegrationTest
  test "user toggles their project progress preference without needing their password" do
    user = users(:juan)
    assert user.show_project_progress?

    post user_session_path, params: { user: { email: user.email, password: "password123" } }
    assert_redirected_to root_path

    patch user_preferences_path, params: { user: { show_project_progress: "0" } }
    assert_redirected_to edit_user_registration_path
    assert_not user.reload.show_project_progress?

    patch user_preferences_path, params: { user: { show_project_progress: "1" } }
    assert user.reload.show_project_progress?
  end

  test "request without a user param does not crash" do
    user = users(:juan)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }

    patch user_preferences_path
    assert_redirected_to edit_user_registration_path
    assert_not user.reload.show_project_progress?
  end
end
