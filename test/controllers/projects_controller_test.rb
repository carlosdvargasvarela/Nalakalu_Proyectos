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

  test "show renders a Gantt column for each show_in_gantt field, with the project's value shown once" do
    project = Project.create!(
      project_type: project_types(:instalaciones), name: "Torre Norte",
      custom_fields: { cliente: "Acme S.A." }
    )
    get project_path(project)
    assert_response :success
    assert_select "table th", text: "Cliente"
    assert_select "table td", text: "Acme S.A.", count: 1
  end

  test "show renders the Gantt chart container with one task per stage" do
    project = Project.create!(
      project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {}
    )
    get project_path(project)
    assert_response :success
    assert_select "#gantt"
    assert_select "script#gantt-tasks", text: /#{project.project_stages.first.name}/
  end

  test "index shows an edit link for each project" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get projects_path
    assert_select "a[href=?]", edit_project_path(project), text: "Editar"
  end

  test "show has an edit link" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_path(project)
    assert_select "a[href=?]", edit_project_path(project), text: "Editar"
  end

  test "show colors each stage's Gantt bar by its stage_template's color" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    stage_templates(:produccion).update!(color: "#ff0000")

    get project_path(project)
    assert_response :success
    assert_match(
      /\.bar-wrapper\.stage-color-#{stage_templates(:produccion).id}\s*\.bar\s*\{\s*fill:\s*#ff0000;?\s*\}/,
      response.body
    )
  end

  test "dashboard shows one row per project across all types by default" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get dashboard_projects_path
    assert_response :success
    assert_select "script#management-gantt-tasks", text: /#{project.name}/
  end

  test "dashboard filters by project_type" do
    other_type = ProjectType.create!(name: "Mantenimiento", slug: "mantenimiento")
    torre = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    otro = Project.create!(project_type: other_type, name: "Proyecto Otro Tipo", custom_fields: {})

    get dashboard_projects_path, params: { project_type_id: other_type.id }
    assert_response :success
    assert_match(/#{otro.name}/, response.body)
    assert_no_match(/#{torre.name}/, response.body)
  end

  test "dashboard filters by status" do
    torre = Project.create!(
      project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {}, status: "active"
    )
    vieja = Project.create!(
      project_type: project_types(:instalaciones), name: "Torre Vieja", custom_fields: {}, status: "archived"
    )

    get dashboard_projects_path, params: { status: "archived" }
    assert_response :success
    assert_match(/#{vieja.name}/, response.body)
    assert_no_match(/#{torre.name}/, response.body)
  end

  test "dashboard shows a message when no projects match the filters" do
    get dashboard_projects_path, params: { status: "nonexistent-status" }
    assert_response :success
    assert_select "body", /No hay proyectos con estos filtros/
  end

  test "index excludes archived projects" do
    Project.create!(project_type: project_types(:instalaciones), name: "Activo", custom_fields: {})
    Project.create!(
      project_type: project_types(:instalaciones), name: "Archivado", custom_fields: {}, status: "archived"
    )
    get projects_path
    assert_response :success
    assert_select "body", /Activo/
    assert_select "body", text: /Archivado/, count: 0
  end

  test "index shows an archive button for each project" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get projects_path
    assert_select "form[action=?]", project_path(project) do
      assert_select "input[value=?]", "Archivar"
    end
  end

  test "archiving a project via update sets status to archived" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    patch project_path(project), params: { project: { status: "archived" } }
    assert_redirected_to project_path(project)
    assert_equal "archived", project.reload.status
  end
end
