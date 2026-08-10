require "test_helper"

class HelpButtonTest < ActionDispatch::IntegrationTest
  test "a page with a doc file shows the contextual help button with the right topic" do
    sign_in users(:juan)
    get admin_project_types_path
    assert_response :success
    assert_select "button[data-help-topic-value=?]", "admin/project_types"
  end

  test "a page without a doc file does not show the contextual help button" do
    get new_user_session_path
    assert_response :success
    assert_select "button[data-controller=?]", "help", count: 0
  end
end
