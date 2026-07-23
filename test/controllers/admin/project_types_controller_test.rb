require "test_helper"

class Admin::ProjectTypesControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:juan) }

  test "index lists project types" do
    get admin_project_types_path
    assert_response :success
    assert_select "body", /Instalaciones/
  end

  test "create adds a new project type" do
    assert_difference("ProjectType.count", 1) do
      post admin_project_types_path, params: { project_type: { name: "Mantenimiento", slug: "mantenimiento" } }
    end
    assert_redirected_to admin_project_type_path(ProjectType.last)
  end

  test "create with blank name re-renders form with error" do
    assert_no_difference("ProjectType.count") do
      post admin_project_types_path, params: { project_type: { name: "", slug: "x" } }
    end
    assert_response :unprocessable_entity
  end

  test "show displays field definitions and stage templates" do
    get admin_project_type_path(project_types(:instalaciones))
    assert_response :success
    assert_select "body", /Cliente/
    assert_select "body", /Producción/
  end

  test "destroy removes a project type with no projects" do
    empty_type = ProjectType.create!(name: "Vacío", slug: "vacio")
    assert_difference("ProjectType.count", -1) do
      delete admin_project_type_path(empty_type)
    end
  end

  test "index links to installers admin" do
    get admin_project_types_path
    assert_response :success
    assert_select "a[href=?]", admin_installers_path, text: "Instaladores"
  end
end
