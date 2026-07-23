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

  test "show displays each custom field's value exactly once (no duplicate Gantt-columns table)" do
    project = Project.create!(
      project_type: project_types(:instalaciones), name: "Torre Norte",
      custom_fields: { cliente: "Acme S.A." }
    )
    get project_path(project)
    assert_response :success
    assert_equal 1, response.body.scan("Acme S.A.").size
  end

  test "show displays a status badge and an archive button" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_path(project)
    assert_response :success
    assert_select "span.badge.bg-success", "Activo"
    assert_select "form[action=?]", project_path(project) do
      assert_select "input[value=?]", "Archivar"
    end
  end

  test "show groups Datos and Cronograma into cards" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_path(project)
    assert_response :success
    assert_select ".card .card-header", "Datos"
    assert_select ".card .card-header", "Cronograma"
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

  test "show colors each stage's Gantt bar by its stage_template's color, including hover/active states" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    stage_templates(:produccion).update!(color: "#ff0000")
    id = stage_templates(:produccion).id

    get project_path(project)
    assert_response :success
    assert_match(/\.gantt \.bar-wrapper\.stage-color-#{id} \.bar,/, response.body)
    assert_match(/\.gantt \.bar-wrapper\.stage-color-#{id}:hover \.bar,/, response.body)
    assert_match(/\.gantt \.bar-wrapper\.stage-color-#{id}\.active \.bar \{\s*fill:\s*#ff0000;?\s*\}/, response.body)
  end

  test "index colors a project's Gantt bar by its assigned installer" do
    installer = installers(:juan_perez)
    installer.update!(color: "#00ff00")
    Project.create!(
      project_type: project_types(:instalaciones), name: "Torre Norte",
      custom_fields: { instalador: installer.id }
    )

    get projects_path
    assert_response :success
    assert_match(/\.gantt \.bar-wrapper\.installer-color-#{installer.id} \.bar,/, response.body)
    assert_match(/\.gantt \.bar-wrapper\.installer-color-#{installer.id}:hover \.bar,/, response.body)
    assert_match(/\.gantt \.bar-wrapper\.installer-color-#{installer.id}\.active \.bar \{\s*fill:\s*#00ff00;?\s*\}/, response.body)
  end

  test "index colors a project with no installer assigned yet using the default gray" do
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})

    get projects_path
    assert_response :success
    assert_match(/\.gantt \.bar-wrapper\.installer-color-none \.bar,/, response.body)
    assert_match(/\.gantt \.bar-wrapper\.installer-color-none\.active \.bar \{\s*fill:\s*#6c757d;?\s*\}/, response.body)
  end

  test "index shows one Gantt task per project by default" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get projects_path
    assert_response :success
    assert_select "script#gantt-tasks", text: /#{project.name}/
  end

  test "index configures the Gantt in Spanish with a read-only snap-back on drag" do
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get projects_path
    assert_response :success
    assert_match(/language:\s*"es"/, response.body)
    assert_match(/on_date_change:\s*function\s*\(\)\s*\{\s*gantt\.refresh\(tasks\);\s*\}/, response.body)
  end

  test "index filters by project_type" do
    other_type = ProjectType.create!(name: "Mantenimiento", slug: "mantenimiento")
    torre = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    otro = Project.create!(project_type: other_type, name: "Proyecto Otro Tipo", custom_fields: {})

    get projects_path, params: { project_type_id: other_type.id }
    assert_response :success
    assert_match(/#{otro.name}/, response.body)
    assert_no_match(/#{torre.name}/, response.body)
  end

  test "index filters by status" do
    torre = Project.create!(
      project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {}, status: "active"
    )
    vieja = Project.create!(
      project_type: project_types(:instalaciones), name: "Torre Vieja", custom_fields: {}, status: "archived"
    )

    get projects_path, params: { status: "archived" }
    assert_response :success
    assert_match(/#{vieja.name}/, response.body)
    assert_no_match(/#{torre.name}/, response.body)
  end

  test "index filters by installer" do
    otro_instalador = Installer.create!(name: "Otro Instalador")
    con_juan = Project.create!(
      project_type: project_types(:instalaciones), name: "Con Juan", custom_fields: { instalador: installers(:juan_perez).id }
    )
    con_otro = Project.create!(
      project_type: project_types(:instalaciones), name: "Con Otro", custom_fields: { instalador: otro_instalador.id }
    )

    get projects_path, params: { installer_id: installers(:juan_perez).id }
    assert_response :success
    assert_match(/#{con_juan.name}/, response.body)
    assert_no_match(/#{con_otro.name}/, response.body)
  end

  test "index shows a message and no Gantt when no projects match the filters" do
    get projects_path, params: { status: "nonexistent-status" }
    assert_response :success
    assert_select "body", /No hay proyectos con estos filtros/
    assert_select "#gantt", count: 0
  end

  test "index excludes archived projects by default" do
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

  test "show renders an editable table row for each stage" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_path(project)
    assert_response :success
    project.project_stages.each do |stage|
      assert_select "input[type=hidden][value=?]", stage.id.to_s
    end
    assert_select "input[name$='[progress_percent]']", count: project.project_stages.count
  end

  test "updating project_stages_attributes changes stage dates and progress" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    stage = project.project_stages.order(:id).first

    patch project_path(project), params: {
      project: {
        project_stages_attributes: {
          "0" => { id: stage.id, start_date: "2026-08-01", end_date: "2026-08-10", progress_percent: 60 }
        }
      }
    }

    assert_redirected_to project_path(project)
    stage.reload
    assert_equal Date.new(2026, 8, 1), stage.start_date
    assert_equal Date.new(2026, 8, 10), stage.end_date
    assert_equal 60, stage.progress_percent
  end

  test "index shows the project status as a Spanish badge, not the raw value" do
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get projects_path
    assert_response :success
    assert_select "span.badge.bg-success", "Activo"
    assert_select "body", text: /\bactive\b/, count: 0
  end

  test "index shows Spanish labels in the status filter while keeping English values" do
    Project.create!(
      project_type: project_types(:instalaciones), name: "Torre Vieja", custom_fields: {}, status: "archived"
    )
    get projects_path
    assert_response :success
    assert_select "select#status option[value=?]", "archived", text: "Archivado"
  end

  test "update responds with JSON stage data when Accept is application/json" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    stage = project.project_stages.order(:id).first

    patch project_path(project), params: {
      project: {
        project_stages_attributes: { "0" => { id: stage.id, start_date: "2026-08-01", end_date: "2026-08-10", progress_percent: 60 } }
      }
    }, as: :json

    assert_response :success
    body = JSON.parse(response.body)
    updated = body.find { |s| s["id"] == stage.id }
    assert_equal "2026-08-01", updated["start_date"]
    assert_equal "2026-08-10", updated["end_date"]
    assert_equal 60, updated["progress_percent"]
  end

  test "update with invalid data returns a 422 JSON error when Accept is application/json" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    stage = project.project_stages.order(:id).first

    patch project_path(project), params: {
      project: {
        project_stages_attributes: { "0" => { id: stage.id, progress_percent: 150 } }
      }
    }, as: :json

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert body["errors"].any?
  end

  test "show's Gantt script saves drag changes via fetch and syncs the stage table" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_path(project)
    assert_response :success
    assert_match(/function saveStage\(/, response.body)
    assert_match(/on_date_change:\s*function\s*\(task,\s*start,\s*end\)/, response.body)
    assert_match(/on_progress_change:\s*function\s*\(task,\s*progress\)/, response.body)
    assert_match(/toDateInputValue/, response.body)
  end

  test "tracker defaults to the first project type when none is given" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get tracker_projects_path
    assert_response :success
    assert_select "body", /#{project.name}/
  end

  test "tracker filters by the given project type" do
    other_type = ProjectType.create!(name: "Mantenimiento", slug: "mantenimiento")
    torre = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    otro = Project.create!(project_type: other_type, name: "Proyecto Otro Tipo", custom_fields: {})

    get tracker_projects_path, params: { project_type_id: other_type.id }
    assert_response :success
    assert_match(/#{otro.name}/, response.body)
    assert_no_match(/#{torre.name}/, response.body)
  end

  test "tracker excludes archived projects" do
    activo = Project.create!(project_type: project_types(:instalaciones), name: "Activo", custom_fields: {})
    Project.create!(
      project_type: project_types(:instalaciones), name: "Archivado", custom_fields: {}, status: "archived"
    )
    get tracker_projects_path
    assert_response :success
    assert_match(/#{activo.name}/, response.body)
    assert_no_match(/Archivado/, response.body)
  end

  test "tracker shows each project's show_in_gantt fields and an editable stage table" do
    project = Project.create!(
      project_type: project_types(:instalaciones), name: "Torre Norte",
      custom_fields: { cliente: "Acme S.A." }
    )
    get tracker_projects_path
    assert_response :success
    assert_select "body", /Cliente/
    assert_select "body", /Acme S\.A\./
    assert_select "input[name*='[start_date]']", count: project.project_stages.count
  end

  test "tracker saves a project's stages independently of other projects" do
    torre = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    otra = Project.create!(project_type: project_types(:instalaciones), name: "Otra Torre", custom_fields: {})
    stage = torre.project_stages.order(:id).first
    otra_stage = otra.project_stages.order(:id).first

    patch project_path(torre), params: {
      project: { project_stages_attributes: { "0" => { id: stage.id, progress_percent: 80 } } }
    }

    assert_redirected_to project_path(torre)
    assert_equal 80, stage.reload.progress_percent
    assert_equal 0, otra_stage.reload.progress_percent
  end

  test "tracker shows a message when there are no project types at all" do
    ProjectType.destroy_all
    get tracker_projects_path
    assert_response :success
    assert_select "body", /No hay tipos de proyecto configurados todavía/
  end
end
