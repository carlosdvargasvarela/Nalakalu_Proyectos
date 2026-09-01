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

  test "navbar includes a link to Responsables for admin" do
    sign_in users(:juan)
    get root_path
    assert_response :success
    assert_select "nav a[href=?]", admin_responsibles_path
  end

  test "navbar does not show the Responsables link to a gerente" do
    sign_in users(:carla)
    get root_path
    assert_response :success
    assert_select "nav a[href=?]", admin_responsibles_path, count: 0
  end

  test "navbar includes a link to Tipos de asociación for admin" do
    sign_in users(:juan)
    get root_path
    assert_response :success
    assert_select "nav a[href=?]", admin_project_type_associations_path
  end

  test "navbar does not show the Tipos de asociación link to a gerente" do
    sign_in users(:carla)
    get root_path
    assert_response :success
    assert_select "nav a[href=?]", admin_project_type_associations_path, count: 0
  end

  test "navbar includes the theme toggle button" do
    sign_in users(:juan)
    get root_path
    assert_response :success
    assert_select "nav button[data-action=?]", "click->theme#toggle"
  end

  test "navbar shows a badge with the pending stage dates count next to Proyectos" do
    project_types(:instalaciones).update!(require_stage_dates: true)
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})

    sign_in users(:juan)
    get root_path
    assert_response :success
    assert_select "nav a[href=?] + .badge", projects_path, "1"
  end

  test "navbar shows no badge when there are no pending projects" do
    sign_in users(:juan)
    get root_path
    assert_response :success
    assert_select "nav a[href=?] + .badge", projects_path, count: 0
  end

  test "layout's anti-flash script sets data-theme alongside data-bs-theme, for frappe-gantt" do
    sign_in users(:juan)
    get root_path
    assert_response :success
    assert_match(/document\.documentElement\.dataset\.bsTheme = document\.documentElement\.dataset\.theme = /, response.body)
  end

  test "theme controller sets data-theme alongside data-bs-theme, for frappe-gantt" do
    source = Rails.root.join("app/javascript/controllers/theme_controller.js").read
    assert_match(/setAttribute\("data-theme",\s*theme\)/, source)
  end

  test "navbar includes the help menu with every topic" do
    sign_in users(:juan)
    get root_path
    assert_response :success
    assert_select "#help-menu-modal button[data-help-topic-value=?]", "projects"
    assert_select "#help-menu-modal button[data-help-topic-value=?]", "admin/users"
  end

  test "navbar does not show the help menu to anonymous visitors" do
    get new_user_session_path
    assert_response :success
    assert_select "#help-menu-modal", count: 0
    assert_select "button[data-bs-target=?]", "#help-menu-modal", count: 0
  end

  test "flash notice renders as a dismissible success toast" do
    sign_in users(:juan)
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    patch bulk_assign_responsible_projects_path, params: {
      project_type_slug: project.project_type.slug,
      project_ids: [ project.id ],
      responsible_type_id: responsible_types(:instalador).id,
      responsible_id: responsibles(:ana_gomez).id
    }
    follow_redirect!
    assert_response :success
    assert_select "#flash-toasts .toast.text-bg-success[data-controller=?]", "toast"
  end

  test "flash alert renders as a dismissible danger toast" do
    sign_in users(:juan)
    patch bulk_assign_responsible_projects_path, params: { project_type_slug: project_types(:instalaciones).slug }
    follow_redirect!
    assert_response :success
    assert_select "#flash-toasts .toast.text-bg-danger[data-controller=?]", "toast"
  end
end
