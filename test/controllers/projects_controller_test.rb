require "test_helper"

class ProjectsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:juan) }

  test "index lists projects" do
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get projects_path
    assert_response :success
    assert_select "body", /Torre Norte/
  end

  test "new renders one input per field_definition of the selected type" do
    get new_project_path(project_type_id: project_types(:instalaciones).id)
    assert_response :success
    assert_select "input[name=?]", "project[custom_fields][cliente]"
    assert_select "select[name=?]", "project[custom_fields][instalador]"
  end

  test "create with valid custom_fields builds the project and its stages" do
    assert_difference("Project.count", 1) do
      post projects_path, params: {
        project: {
          project_type_id: project_types(:instalaciones).id,
          name: "Torre Sur",
          custom_fields: { cliente: "Acme S.A.", instalador: installers(:juan_perez).id }
        }
      }
    end
    project = Project.order(:id).last
    assert_redirected_to project_path(project)
    assert_equal 5, project.project_stages.count
  end

  test "create with invalid custom_fields re-renders form with error" do
    assert_no_difference("Project.count") do
      post projects_path, params: {
        project: {
          project_type_id: project_types(:instalaciones).id,
          name: "Torre Sur",
          custom_fields: { cliente: "Acme S.A.", instalador: 999_999 }
        }
      }
    end
    assert_response :unprocessable_entity
  end

  test "show displays custom fields and the stage table" do
    project = Project.create!(
      project_type: project_types(:instalaciones), name: "Torre Norte",
      custom_fields: { cliente: "Acme S.A." }
    )
    get project_path(project)
    assert_response :success
    assert_select "body", /Acme S.A./
    assert_select "body", /Producción/
  end

  test "show renders a Gantt column for each show_in_gantt field, with the project's value on every stage row" do
    project = Project.create!(
      project_type: project_types(:instalaciones), name: "Torre Norte",
      custom_fields: { cliente: "Acme S.A." }
    )
    get project_path(project)
    assert_response :success
    assert_select "table th", text: "Cliente"
    assert_select "table td", text: "Acme S.A.", count: project.project_stages.count
  end
end
