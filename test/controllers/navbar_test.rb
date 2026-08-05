require "test_helper"

class NavbarTest < ActionDispatch::IntegrationTest
  test "navbar shows session-aware links when signed in" do
    sign_in users(:juan)
    get root_path
    follow_redirect!
    assert_response :success
    assert_select "nav a[href=?]", projects_path
    assert_select "nav a[href=?]", admin_project_types_path
    assert_select "nav", /juan@example\.com/
  end

  test "navbar includes a link to Seguimiento" do
    sign_in users(:juan)
    get root_path
    follow_redirect!
    assert_response :success
    assert_select "nav a[href=?]", tracker_projects_path
  end

  test "navbar includes a link to Importar" do
    sign_in users(:juan)
    get root_path
    follow_redirect!
    assert_response :success
    assert_select "nav a[href=?]", new_import_path
  end

  test "navbar includes a link to Responsables for admin" do
    sign_in users(:juan)
    get root_path
    follow_redirect!
    assert_response :success
    assert_select "nav a[href=?]", admin_responsibles_path
  end

  test "navbar does not show the Responsables link to a gerente" do
    sign_in users(:carla)
    get root_path
    follow_redirect!
    assert_response :success
    assert_select "nav a[href=?]", admin_responsibles_path, count: 0
  end

  test "navbar includes a link to Tipos de asociación for admin" do
    sign_in users(:juan)
    get root_path
    follow_redirect!
    assert_response :success
    assert_select "nav a[href=?]", admin_project_type_associations_path
  end

  test "navbar does not show the Tipos de asociación link to a gerente" do
    sign_in users(:carla)
    get root_path
    follow_redirect!
    assert_response :success
    assert_select "nav a[href=?]", admin_project_type_associations_path, count: 0
  end

  test "navbar includes the theme toggle button" do
    sign_in users(:juan)
    get root_path
    follow_redirect!
    assert_response :success
    assert_select "nav button[data-action=?]", "click->theme#toggle"
  end

  test "navbar shows a badge with the pending stage dates count next to Proyectos" do
    project_types(:instalaciones).update!(require_stage_dates: true)
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})

    sign_in users(:juan)
    get root_path
    follow_redirect!
    assert_response :success
    assert_select "nav a[href=?] + .badge", projects_path, "1"
  end

  test "navbar shows no badge when there are no pending projects" do
    sign_in users(:juan)
    get root_path
    follow_redirect!
    assert_response :success
    assert_select "nav a[href=?] + .badge", projects_path, count: 0
  end
end
