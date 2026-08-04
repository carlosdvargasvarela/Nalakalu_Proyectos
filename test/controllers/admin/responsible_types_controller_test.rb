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
    type = responsible_types(:disenador)
    responsible = Responsible.create!(name: "Diseñador")
    ResponsibleProjectType.create!(responsible: responsible, project_type: @project_type, responsible_type: type)
    ProjectResponsible.create!(project: project, responsible: responsible, responsible_type: type)

    assert_difference("ProjectResponsible.count", -1) do
      delete admin_project_type_responsible_type_path(@project_type, type)
    end
  end

  test "create saves default_in_filter" do
    post admin_project_type_responsible_types_path(@project_type), params: {
      responsible_type: { name: "Electricista", default_in_filter: "1" }
    }
    assert ResponsibleType.order(:id).last.default_in_filter
  end

  test "update saves default_in_filter and clears the previous default" do
    instalador = responsible_types(:instalador)
    disenador = responsible_types(:disenador)
    instalador.update!(default_in_filter: true)

    patch admin_project_type_responsible_type_path(@project_type, disenador), params: {
      responsible_type: { name: disenador.name, default_in_filter: "1" }
    }

    assert_redirected_to admin_project_type_path(@project_type)
    assert disenador.reload.default_in_filter
    assert_not instalador.reload.default_in_filter
  end

  test "new and edit show the default_in_filter checkbox" do
    get new_admin_project_type_responsible_type_path(@project_type)
    assert_response :success
    assert_select "input[type=checkbox][name=?]", "responsible_type[default_in_filter]"
  end
end
