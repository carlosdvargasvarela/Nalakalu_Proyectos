require "test_helper"

class Admin::ResponsibleTypesControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:juan) }
  setup { @project_type = project_types(:instalaciones) }

  test "create adds a responsible_type to the project type" do
    assert_difference("@project_type.responsible_types.count", 1) do
      post admin_project_type_responsible_types_path(@project_type), params: {
        responsible_type: { name: "Electricista" }
      }
    end
    assert_redirected_to admin_project_type_path(@project_type)
  end

  test "create with blank name re-renders form with error" do
    assert_no_difference("@project_type.responsible_types.count") do
      post admin_project_type_responsible_types_path(@project_type), params: {
        responsible_type: { name: "" }
      }
    end
    assert_response :unprocessable_entity
  end

  test "update saves the name" do
    type = responsible_types(:disenador)
    patch admin_project_type_responsible_type_path(@project_type, type), params: {
      responsible_type: { name: "Diseñador Senior" }
    }
    assert_redirected_to admin_project_type_path(@project_type)
    assert_equal "Diseñador Senior", type.reload.name
  end

  test "destroy removes a responsible_type" do
    type = responsible_types(:disenador)
    assert_difference("@project_type.responsible_types.count", -1) do
      delete admin_project_type_responsible_type_path(@project_type, type)
    end
  end

  test "destroy cascades to its project_responsibles" do
    project = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: {})
    responsible = responsibles(:ana_gomez)
    type = responsible_types(:disenador)
    ProjectResponsible.create!(project: project, responsible: responsible, responsible_type: type)

    assert_difference("ProjectResponsible.count", -1) do
      delete admin_project_type_responsible_type_path(@project_type, type)
    end
  end
end
