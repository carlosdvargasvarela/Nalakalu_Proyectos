require "test_helper"

class NavbarTest < ActionDispatch::IntegrationTest
  test "navbar shows session-aware links when signed in" do
    sign_in users(:juan)
    get root_path
    assert_response :success
    assert_select "nav a[href=?]", projects_path
    assert_select "nav a[href=?]", admin_project_types_path
    assert_select "nav", /juan@example\.com/
  end

  test "navbar includes a link to Seguimiento" do
    sign_in users(:juan)
    get root_path
    assert_response :success
    assert_select "nav a[href=?]", tracker_projects_path
  end

  test "navbar includes a link to Importar" do
    sign_in users(:juan)
    get root_path
    assert_response :success
    assert_select "nav a[href=?]", new_import_path
  end
end
