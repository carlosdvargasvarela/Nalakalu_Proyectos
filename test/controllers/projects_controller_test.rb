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

  test "new and edit show the submit button in Spanish" do
    get new_project_path(project_type_id: project_types(:instalaciones).id)
    assert_response :success
    assert_select "input[value=?]", "Crear Proyecto"

    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get edit_project_path(project)
    assert_response :success
    assert_select "input[value=?]", "Actualizar Proyecto"
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

  test "index's Editar and Archivar buttons are wrapped in a flex container with icons" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get projects_path
    assert_response :success
    assert_select "td .d-flex.gap-2 a.btn i.bi-pencil"
    assert_select "td .d-flex.gap-2 form button i.bi-archive"
  end

  test "show's Editar button includes the pencil icon" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_path(project)
    assert_response :success
    assert_select "a.btn i.bi-pencil"
  end

  test "layout loads Bootstrap Icons" do
    get projects_path
    assert_response :success
    assert_match(/bootstrap-icons/, response.body)
  end

  test "show displays a status badge and an archive button" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_path(project)
    assert_response :success
    assert_select "span.badge.bg-success", "Activo"
    assert_select "form[action=?]", project_path(project) do
      assert_select "button", text: /Archivar/
    end
  end

  test "show renders the project data as a graphite band and keeps the Cronograma card" do
    project = Project.create!(
      project_type: project_types(:instalaciones), name: "Torre Norte",
      custom_fields: { cliente: "Acme S.A." }
    )
    get project_path(project)
    assert_response :success
    assert_select ".bg-primary", /Acme S\.A\./
    assert_select ".card .card-header", "Cronograma"
  end

  test "tracker renders each project's data as a graphite band without a bordered card" do
    installer = installers(:juan_perez)
    project = Project.create!(
      project_type: project_types(:instalaciones), name: "Torre Norte",
      custom_fields: { cliente: "Acme S.A.", instalador: installer.id }
    )
    get tracker_projects_path
    assert_response :success
    assert_select ".bg-primary", /Acme S\.A\./
    assert_select ".card", count: 0
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
    assert_select "script#gantt-tasks-#{project_types(:instalaciones).slug}", text: /#{project.name}/
  end

  test "index configures the Gantt in Spanish with native readonly options" do
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get projects_path
    assert_response :success
    assert_match(/language:\s*"es"/, response.body)
    assert_match(/readonly_dates:\s*true/, response.body)
    assert_match(/readonly_progress:\s*true/, response.body)
  end

  test "index's Gantt click handler is wired via the on_click constructor option, not gantt.on" do
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get projects_path
    assert_response :success
    assert_match(/on_click:\s*function\s*\(task\)\s*\{\s*window\.location\s*=\s*task\.edit_url;\s*\}/, response.body)
    assert_no_match(/gantt\.on\(/, response.body)
  end

  test "index's Gantt overrides the progress-bar fill for visibility against custom bar colors" do
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get projects_path
    assert_response :success
    assert_match(/\.gantt \.bar-progress \{\s*fill:\s*rgba\(0,\s*0,\s*0,\s*0\.25\);?\s*\}/, response.body)
  end

  test "index configures the Gantt with a fixed container height instead of manual scroll CSS" do
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get projects_path
    assert_response :success
    slug = project_types(:instalaciones).slug
    assert_select "#gantt-#{slug}[style]", count: 0
    assert_match(/container_height:\s*630/, response.body)
  end

  test "index loads frappe-gantt 1.2.2" do
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get projects_path
    assert_response :success
    assert_match(%r{frappe-gantt@1\.2\.2/dist/frappe-gantt\.css}, response.body)
    assert_match(%r{frappe-gantt@1\.2\.2/dist/frappe-gantt\.umd\.js}, response.body)
    assert_no_match(/frappe-gantt@0\.6\.1/, response.body)
  end

  test "index shows Día/Semana/Mes view-mode buttons for the Gantt" do
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get projects_path
    assert_response :success
    slug = project_types(:instalaciones).slug
    assert_select "#view-mode-#{slug} button", text: "Día"
    assert_select "#view-mode-#{slug} button", text: "Semana"
    assert_select "#view-mode-#{slug} button", text: "Mes"
  end

  test "index's Gantt shows only the filtered stage's date range for each project, not the full project span" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    stage = project.project_stages.find_by(name: "Instalación")
    stage.update!(start_date: Date.new(2026, 9, 1), end_date: Date.new(2026, 9, 10))
    slug = project_types(:instalaciones).slug

    get projects_path, params: { sections: { slug => { stage_name: "Instalación" } } }
    assert_response :success
    assert_select "script#gantt-tasks-#{slug}" do |elements|
      tasks = JSON.parse(elements.first.text)
      task = tasks.find { |t| t["id"] == project.id.to_s }
      assert_equal "2026-09-01", task["start"]
      assert_equal "2026-09-10", task["end"]
    end
  end

  test "index's Gantt section omits every project when the filtered stage doesn't exist for that type" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    slug = project_types(:instalaciones).slug

    get projects_path, params: { sections: { slug => { stage_name: "Etapa Inexistente" } } }
    assert_response :success
    assert_select "script#gantt-tasks-#{slug}" do |elements|
      tasks = JSON.parse(elements.first.text)
      assert_nil tasks.find { |t| t["id"] == project.id.to_s }
    end
  end

  test "index's Gantt without a stage filter still shows each project's full range" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    slug = project_types(:instalaciones).slug
    get projects_path
    assert_response :success
    assert_select "script#gantt-tasks-#{slug}" do |elements|
      tasks = JSON.parse(elements.first.text)
      task = tasks.find { |t| t["id"] == project.id.to_s }
      first, last = project.gantt_window
      assert_equal first.to_s, task["start"]
      assert_equal last.to_s, task["end"]
    end
  end

  test "index's stage filter doesn't affect that section's Listado table or KPI cards" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Con Etapa", custom_fields: {})
    slug = project_types(:instalaciones).slug

    get projects_path, params: { sections: { slug => { stage_name: "Etapa Inexistente" } } }
    assert_response :success
    assert_select ".card .display-6", "1"
    assert_select "a[href=?]", project_path(project)
  end

  test "index shows each project type as its own section, listing only that type's own projects" do
    other_type = ProjectType.create!(name: "Mantenimiento", slug: "mantenimiento")
    torre = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    otro = Project.create!(project_type: other_type, name: "Proyecto Otro Tipo", custom_fields: {})

    get projects_path
    assert_response :success
    assert_select "a[href=?]", project_path(torre)
    assert_select "a[href=?]", project_path(otro)
    assert_select ".accordion-item", count: ProjectType.count
  end

  test "index's accordion expands the first section and collapses the rest" do
    ProjectType.create!(name: "Mantenimiento", slug: "mantenimiento")
    get projects_path
    assert_response :success
    assert_select ".accordion-collapse.show", count: 1
  end

  test "index's filter for one section doesn't affect another section's results" do
    other_type = ProjectType.create!(name: "Mantenimiento", slug: "mantenimiento")
    torre = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {}, status: "active")
    otro = Project.create!(project_type: other_type, name: "Proyecto Otro Tipo", custom_fields: {}, status: "active")

    get projects_path, params: { sections: { project_types(:instalaciones).slug => { status: "archived" } } }
    assert_response :success
    assert_select "a[href=?]", project_path(torre), count: 0
    assert_select "a[href=?]", project_path(otro)
  end

  test "index's pagination for one section doesn't affect another section's page" do
    other_type = ProjectType.create!(name: "Mantenimiento", slug: "mantenimiento")
    25.times { |n| Project.create!(project_type: project_types(:instalaciones), name: "Proyecto #{n}", custom_fields: {}) }
    otro = Project.create!(project_type: other_type, name: "Proyecto Otro Tipo", custom_fields: {})

    get projects_path, params: { sections: { project_types(:instalaciones).slug => { page: 2 } } }
    assert_response :success
    assert_select "a[href=?]", project_path(otro)
  end

  test "index's Etapa dropdown only lists stages belonging to that section's own project type" do
    other_type = ProjectType.create!(name: "Mantenimiento", slug: "mantenimiento")
    StageTemplate.create!(project_type: other_type, name: "Etapa De Otro Tipo", position: 1)

    get projects_path
    assert_response :success
    assert_select "select#sections_#{project_types(:instalaciones).slug}_stage_name option", text: "Instalación"
    assert_select "select#sections_#{project_types(:instalaciones).slug}_stage_name option", text: "Etapa De Otro Tipo", count: 0
  end

  test "index's ids are unique per section (Gantt, bulk-assign form, select-all checkbox)" do
    other_type = ProjectType.create!(name: "Mantenimiento", slug: "mantenimiento")
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    Project.create!(project_type: other_type, name: "Proyecto Otro Tipo", custom_fields: {})

    get projects_path
    assert_response :success
    assert_select "#gantt-#{project_types(:instalaciones).slug}"
    assert_select "#gantt-#{other_type.slug}"
    assert_select "#bulk-assign-form-#{project_types(:instalaciones).slug}"
    assert_select "#bulk-assign-form-#{other_type.slug}"
    assert_select "#select-all-projects-#{project_types(:instalaciones).slug}"
    assert_select "#select-all-projects-#{other_type.slug}"
  end

  test "index shows an Etapa dropdown with the distinct stage template names" do
    get projects_path
    assert_response :success
    slug = project_types(:instalaciones).slug
    assert_select "select#sections_#{slug}_stage_name option", text: "Instalación"
    assert_select "select#sections_#{slug}_stage_name option", text: "Producción"
  end

  test "index filters by status" do
    slug = project_types(:instalaciones).slug
    torre = Project.create!(
      project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {}, status: "active"
    )
    vieja = Project.create!(
      project_type: project_types(:instalaciones), name: "Torre Vieja", custom_fields: {}, status: "archived"
    )

    get projects_path, params: { sections: { slug => { status: "archived" } } }
    assert_response :success
    assert_match(/#{vieja.name}/, response.body)
    assert_no_match(/#{torre.name}/, response.body)
  end

  test "index filters by installer" do
    slug = project_types(:instalaciones).slug
    otro_instalador = Installer.create!(name: "Otro Instalador")
    con_juan = Project.create!(
      project_type: project_types(:instalaciones), name: "Con Juan", custom_fields: { instalador: installers(:juan_perez).id }
    )
    con_otro = Project.create!(
      project_type: project_types(:instalaciones), name: "Con Otro", custom_fields: { instalador: otro_instalador.id }
    )

    get projects_path, params: { sections: { slug => { installer_id: installers(:juan_perez).id } } }
    assert_response :success
    assert_match(/#{con_juan.name}/, response.body)
    assert_no_match(/#{con_otro.name}/, response.body)
  end

  test "index filters by Sin instalador" do
    slug = project_types(:instalaciones).slug
    sin_instalador = Project.create!(
      project_type: project_types(:instalaciones), name: "Sin Instalador", custom_fields: {}
    )
    con_instalador = Project.create!(
      project_type: project_types(:instalaciones), name: "Con Instalador",
      custom_fields: { instalador: installers(:juan_perez).id }
    )

    get projects_path, params: { sections: { slug => { installer_id: "none" } } }
    assert_response :success
    assert_match(/#{sin_instalador.name}/, response.body)
    assert_no_match(/#{con_instalador.name}/, response.body)
  end

  test "index shows a Sin instalador option in the Instalador filter" do
    get projects_path
    assert_response :success
    slug = project_types(:instalaciones).slug
    assert_select "select#sections_#{slug}_installer_id option[value=?]", "none", text: "Sin instalador"
  end

  test "index shows a message and no Gantt when no projects match the filters" do
    slug = project_types(:instalaciones).slug
    get projects_path, params: { sections: { slug => { status: "nonexistent-status" } } }
    assert_response :success
    assert_select "body", /No hay proyectos con estos filtros/
    assert_select "#gantt-#{slug}", count: 0
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
      assert_select "button", text: /Archivar/
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

  test "show's stage table renders a Duración (días) input with no name attribute, per stage" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_path(project)
    assert_response :success
    assert_select ".stage-table th", text: "Duración (días)"
    assert_select ".stage-table input.duracion-input", count: project.project_stages.count
    assert_select ".stage-table input.duracion-input[name]", count: 0
  end

  test "tracker's stage table renders a Duración (días) input with no name attribute, per stage" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get tracker_projects_path
    assert_response :success
    assert_select ".stage-table th", text: "Duración (días)"
    assert_select ".stage-table input.duracion-input", count: project.project_stages.count
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
    slug = project_types(:instalaciones).slug
    assert_select "select#sections_#{slug}_status option[value=?]", "archived", text: "Archivado"
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

  test "show loads frappe-gantt 1.2.2" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_path(project)
    assert_response :success
    assert_match(%r{frappe-gantt@1\.2\.2/dist/frappe-gantt\.css}, response.body)
    assert_match(%r{frappe-gantt@1\.2\.2/dist/frappe-gantt\.umd\.js}, response.body)
    assert_no_match(/frappe-gantt@0\.6\.1/, response.body)
  end

  test "show shows Día/Semana/Mes view-mode buttons for the Gantt" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_path(project)
    assert_response :success
    assert_select "#view-mode-show button", text: "Día"
    assert_select "#view-mode-show button", text: "Semana"
    assert_select "#view-mode-show button", text: "Mes"
  end

  test "show's Gantt still reverts a failed save via gantt.refresh" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_path(project)
    assert_response :success
    assert_match(/gantt\.refresh\(tasks\)/, response.body)
  end

  test "show's Gantt handlers are wired via constructor options, not gantt.on" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_path(project)
    assert_response :success
    assert_match(/on_click:\s*function\s*\(task\)\s*\{\s*window\.location\.hash\s*=\s*"stage-"\s*\+\s*task\.id;\s*\}/, response.body)
    assert_no_match(/gantt\.on\(/, response.body)
  end

  test "show's Gantt overrides the progress-bar fill for visibility against custom bar colors" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_path(project)
    assert_response :success
    assert_match(/\.gantt \.bar-progress \{\s*fill:\s*rgba\(0,\s*0,\s*0,\s*0\.25\);?\s*\}/, response.body)
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

  test "tracker filters by installer" do
    otro_instalador = Installer.create!(name: "Otro Instalador")
    con_juan = Project.create!(
      project_type: project_types(:instalaciones), name: "Con Juan",
      custom_fields: { instalador: installers(:juan_perez).id }
    )
    con_otro = Project.create!(
      project_type: project_types(:instalaciones), name: "Con Otro",
      custom_fields: { instalador: otro_instalador.id }
    )

    get tracker_projects_path, params: { installer_id: installers(:juan_perez).id }
    assert_response :success
    assert_match(/#{con_juan.name}/, response.body)
    assert_no_match(/#{con_otro.name}/, response.body)
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

  test "new shows the project type in the title, wraps the form in a card, and links Cancelar to the list" do
    get new_project_path(project_type_id: project_types(:instalaciones).id)
    assert_response :success
    assert_select "h1", /Instalaciones/
    assert_select ".card form"
    assert_select "a[href=?]", projects_path, text: "Cancelar"
  end

  test "edit shows the project name in the title, wraps the form in a card, and links Cancelar to the project" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get edit_project_path(project)
    assert_response :success
    assert_select "h1", /Torre Norte/
    assert_select ".card form"
    assert_select "a[href=?]", project_path(project), text: "Cancelar"
  end

  test "show displays the project's progress status and overdue badges" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    project.project_stages.order(:id).first.update!(end_date: Date.current - 1.day, progress_percent: 40)

    get project_path(project)
    assert_response :success
    assert_select "span.badge.bg-info", "Iniciado"
    assert_select "span.badge.bg-danger", "Vencido"
  end

  test "tracker displays each project's progress status badge" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get tracker_projects_path
    assert_response :success
    assert_select "span.badge.bg-secondary", "Sin iniciar"
  end

  test "the stage table shows each stage's progress status and overdue badges" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    stage = project.project_stages.order(:id).first
    stage.update!(end_date: Date.current - 1.day, progress_percent: 40)

    get project_path(project)
    assert_response :success
    assert_select "#stage-#{stage.id} span.badge.bg-info", "Iniciado"
    assert_select "#stage-#{stage.id} span.badge.bg-danger", "Vencido"
  end

  test "index shows a Nuevo proyecto dropdown with one link per project type" do
    other_type = ProjectType.create!(name: "Mantenimiento", slug: "mantenimiento")
    get projects_path
    assert_response :success
    assert_select ".dropdown-menu a[href=?]", new_project_path(project_type_id: project_types(:instalaciones).id)
    assert_select ".dropdown-menu a[href=?]", new_project_path(project_type_id: other_type.id)
  end

  test "index shows KPI cards for total, overdue, and finalizado projects" do
    Project.create!(project_type: project_types(:instalaciones), name: "Activo", custom_fields: {})
    vencido = Project.create!(project_type: project_types(:instalaciones), name: "Vencido", custom_fields: {})
    vencido.project_stages.order(:id).first.update!(end_date: Date.current - 1.day, progress_percent: 50)
    finalizado = Project.create!(project_type: project_types(:instalaciones), name: "Finalizado", custom_fields: {})
    finalizado.project_stages.each { |stage| stage.update!(progress_percent: 100) }

    get projects_path
    assert_response :success
    assert_select ".card .display-6", "3"
    assert_select ".card .display-6.text-danger", "1"
    assert_select ".card .display-6.text-success", "1"
  end

  test "index shows progress-status and overdue badges in the table" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    project.project_stages.order(:id).first.update!(end_date: Date.current - 1.day, progress_percent: 40)

    get projects_path
    assert_response :success
    assert_select "table span.badge.bg-info", "Iniciado"
    assert_select "table span.badge.bg-danger", "Vencido"
  end

  test "index wraps the Gantt and the table in cards" do
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get projects_path
    assert_response :success
    assert_select ".card .card-header", "Cronograma"
    assert_select ".card .card-header", "Listado"
  end

  test "new renders the right input for each new data type" do
    project_type = project_types(:instalaciones)
    FieldDefinition.create!(project_type: project_type, key: "cantidad", label: "Cantidad", data_type: "number", position: 10)
    FieldDefinition.create!(project_type: project_type, key: "monto", label: "Monto", data_type: "currency", position: 11)
    FieldDefinition.create!(project_type: project_type, key: "notas", label: "Notas", data_type: "textarea", position: 12)
    FieldDefinition.create!(project_type: project_type, key: "permiso", label: "Permiso", data_type: "boolean", position: 13)

    get new_project_path(project_type_id: project_type.id)
    assert_response :success
    assert_select "input[name=?][type=number]", "project[custom_fields][cantidad]"
    assert_select "input[name=?][type=number]", "project[custom_fields][monto]"
    assert_select "textarea[name=?]", "project[custom_fields][notas]"
    assert_select "input[name=?][type=checkbox]", "project[custom_fields][permiso]"
  end

  test "create with valid new-type custom_fields builds the project" do
    project_type = project_types(:instalaciones)
    FieldDefinition.create!(project_type: project_type, key: "cantidad", label: "Cantidad", data_type: "number", position: 10)

    assert_difference("Project.count", 1) do
      post projects_path, params: {
        project: {
          project_type_id: project_type.id, name: "Torre Sur",
          custom_fields: { cliente: "Acme S.A.", cantidad: "5" }
        }
      }
    end
    assert_equal "5", Project.order(:id).last.custom_fields["cantidad"]
  end

  test "bulk_assign_installer assigns the installer to every selected project" do
    otro_instalador = Installer.create!(name: "Otro Instalador")
    proyecto_a = Project.create!(project_type: project_types(:instalaciones), name: "Proyecto A", custom_fields: {})
    proyecto_b = Project.create!(project_type: project_types(:instalaciones), name: "Proyecto B", custom_fields: {})

    patch bulk_assign_installer_projects_path, params: {
      installer_id: otro_instalador.id, project_ids: [proyecto_a.id, proyecto_b.id]
    }

    assert_redirected_to projects_path
    assert_equal otro_instalador.id.to_s, proyecto_a.reload.custom_fields["instalador"]
    assert_equal otro_instalador.id.to_s, proyecto_b.reload.custom_fields["instalador"]
    follow_redirect!
    assert_match(/Instalador asignado a 2 proyecto\(s\)/, response.body)
  end

  test "bulk_assign_installer preserves existing query params on redirect" do
    installer = installers(:juan_perez)
    project = Project.create!(project_type: project_types(:instalaciones), name: "Proyecto A", custom_fields: {})
    slug = project_types(:instalaciones).slug

    patch bulk_assign_installer_projects_path(sections: { slug => { status: "archived" } }), params: {
      installer_id: installer.id, project_ids: [project.id]
    }

    assert_redirected_to projects_path(sections: { slug => { status: "archived" } })
  end

  test "index's bulk-assign form action preserves the current installer filter" do
    slug = project_types(:instalaciones).slug
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get projects_path, params: { sections: { slug => { installer_id: "none" } } }
    assert_response :success
    assert_select "form#bulk-assign-form-#{slug}[action=?]",
      bulk_assign_installer_projects_path(sections: { slug => { installer_id: "none" } })
  end

  test "bulk_assign_installer without an installer chosen does nothing and redirects with an alert" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Proyecto A", custom_fields: {})

    patch bulk_assign_installer_projects_path, params: { installer_id: "", project_ids: [project.id] }

    assert_redirected_to projects_path
    assert_nil project.reload.custom_fields["instalador"]
    follow_redirect!
    assert_match(/Elegí un instalador y al menos un proyecto/, response.body)
  end

  test "bulk_assign_installer without any project selected does nothing and redirects with an alert" do
    installer = installers(:juan_perez)

    patch bulk_assign_installer_projects_path, params: { installer_id: installer.id, project_ids: [] }

    assert_redirected_to projects_path
    follow_redirect!
    assert_match(/Elegí un instalador y al menos un proyecto/, response.body)
  end

  test "bulk_assign_installer skips a project whose type has no installer-reference field" do
    other_type = ProjectType.create!(name: "Mantenimiento", slug: "mantenimiento")
    installer = installers(:juan_perez)
    con_campo = Project.create!(project_type: project_types(:instalaciones), name: "Con Campo", custom_fields: {})
    sin_campo = Project.create!(project_type: other_type, name: "Sin Campo", custom_fields: {})

    patch bulk_assign_installer_projects_path, params: {
      installer_id: installer.id, project_ids: [con_campo.id, sin_campo.id]
    }

    assert_equal installer.id.to_s, con_campo.reload.custom_fields["instalador"]
    assert_equal({}, sin_campo.reload.custom_fields)
    follow_redirect!
    assert_match(/Instalador asignado a 1 proyecto\(s\)/, response.body)
  end

  test "index renders a bulk-assign form with a checkbox per project, not nested inside another form" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    slug = project_types(:instalaciones).slug
    get projects_path
    assert_response :success

    assert_select "form#bulk-assign-form-#{slug}[action=?]", bulk_assign_installer_projects_path
    assert_select "form#bulk-assign-form-#{slug} select[name=?]", "installer_id"
    assert_select "form#bulk-assign-form-#{slug} input[type=submit][value=?]", "Asignar"
    assert_select "input[type=checkbox][name=?][form=bulk-assign-form-#{slug}]", "project_ids[]", value: project.id.to_s

    doc = Nokogiri::HTML5(response.body)
    bulk_form = doc.at_css("#bulk-assign-form-#{slug}")
    assert_nil bulk_form.at_css("form"), "the archive button's form must not be nested inside the bulk-assign form"
  end

  test "index's select-all checkbox toggles every project checkbox via JS" do
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get projects_path
    assert_response :success
    slug = project_types(:instalaciones).slug
    assert_select "input#select-all-projects-#{slug}[type=checkbox]"
    assert_match(/select-all-projects-#{slug}/, response.body)
    assert_match(/project_ids\[\]/, response.body)
  end

  test "index's pagination Anterior link points to the previous page, not itself" do
    slug = project_types(:instalaciones).slug
    25.times { |n| Project.create!(project_type: project_types(:instalaciones), name: "Proyecto #{n}", custom_fields: {}) }
    get projects_path, params: { sections: { slug => { page: 2 } } }
    assert_response :success
    assert_select "a.page-link[href=?]", projects_path(sections: { slug => { page: 1 } })
  end

  test "index filters by a Desde/Hasta date range that overlaps a project's stages" do
    slug = project_types(:instalaciones).slug
    dentro = Project.create!(project_type: project_types(:instalaciones), name: "Dentro del Rango", custom_fields: {})
    dentro.project_stages.order(:id).first.update!(start_date: Date.new(2026, 3, 1), end_date: Date.new(2026, 3, 10))

    fuera = Project.create!(project_type: project_types(:instalaciones), name: "Fuera del Rango", custom_fields: {})
    fuera.project_stages.each { |s| s.update!(start_date: Date.new(2026, 6, 1), end_date: Date.new(2026, 6, 10)) }

    get projects_path, params: { sections: { slug => { from_date: "2026-02-01", to_date: "2026-04-01" } } }
    assert_response :success
    assert_match(/#{dentro.name}/, response.body)
    assert_no_match(/#{fuera.name}/, response.body)
  end

  test "index without from_date or to_date shows all projects allowed by the other filters" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get projects_path
    assert_response :success
    assert_match(/#{project.name}/, response.body)
  end

  test "index shows Desde and Hasta date fields in the filter form" do
    get projects_path
    assert_response :success
    slug = project_types(:instalaciones).slug
    assert_select "input[type=date][name=?]", "sections[#{slug}][from_date]"
    assert_select "input[type=date][name=?]", "sections[#{slug}][to_date]"
  end

  test "index's Desde/Hasta filter always shows projects with no dated stages, regardless of the range" do
    slug = project_types(:instalaciones).slug
    sin_fechas = Project.create!(project_type: project_types(:instalaciones), name: "Sin Fechas", custom_fields: {})
    fuera = Project.create!(project_type: project_types(:instalaciones), name: "Fuera del Rango", custom_fields: {})
    fuera.project_stages.each { |s| s.update!(start_date: Date.new(2026, 6, 1), end_date: Date.new(2026, 6, 10)) }

    get projects_path, params: { sections: { slug => { from_date: "2026-02-01", to_date: "2026-04-01" } } }
    assert_response :success
    assert_match(/#{sin_fechas.name}/, response.body)
    assert_no_match(/#{fuera.name}/, response.body)
  end

  test "index's q filter matches a project by name" do
    slug = project_types(:instalaciones).slug
    match = Project.create!(project_type: project_types(:instalaciones), name: "Torre del Bosque", custom_fields: {})
    other = Project.create!(project_type: project_types(:instalaciones), name: "Otro Proyecto", custom_fields: {})

    get projects_path, params: { sections: { slug => { q: "Bosque" } } }
    assert_response :success
    assert_match(/#{match.name}/, response.body)
    assert_no_match(/#{other.name}/, response.body)
  end

  test "index's q filter matches a value inside custom_fields, regardless of which field holds it" do
    slug = project_types(:instalaciones).slug
    match = Project.create!(
      project_type: project_types(:instalaciones), name: "Proyecto A",
      custom_fields: { cliente: "Constructora Acme S.R.L." }
    )
    other = Project.create!(
      project_type: project_types(:instalaciones), name: "Proyecto B",
      custom_fields: { cliente: "Otro Cliente" }
    )

    get projects_path, params: { sections: { slug => { q: "Acme" } } }
    assert_response :success
    assert_match(/#{match.name}/, response.body)
    assert_no_match(/#{other.name}/, response.body)
  end

  test "index's q filter is case-insensitive" do
    slug = project_types(:instalaciones).slug
    project = Project.create!(
      project_type: project_types(:instalaciones), name: "Proyecto Mayúsculas",
      custom_fields: { cliente: "CONSTRUCTORA GRANDE" }
    )

    get projects_path, params: { sections: { slug => { q: "constructora grande" } } }
    assert_response :success
    assert_match(/#{project.name}/, response.body)
  end

  test "index's q filter combines with other filters within the same section (AND)" do
    slug = project_types(:instalaciones).slug
    match = Project.create!(
      project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {}, status: "active"
    )
    otro_estado = Project.create!(
      project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {}, status: "archived"
    )

    get projects_path, params: { sections: { slug => { q: "Torre Norte", status: "active" } } }
    assert_response :success
    assert_select "a[href=?]", project_path(match)
    assert_select "a[href=?]", project_path(otro_estado), count: 0
  end

  test "index shows no results when q doesn't match anything" do
    slug = project_types(:instalaciones).slug
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get projects_path, params: { sections: { slug => { q: "esto-no-existe-en-ningun-proyecto" } } }
    assert_response :success
    assert_select "body", /No hay proyectos con estos filtros/
  end

  test "index shows the q search field in the filter form" do
    get projects_path
    assert_response :success
    slug = project_types(:instalaciones).slug
    assert_select "input[type=text][name=?]", "sections[#{slug}][q]"
  end

  test "index paginates the Listado table at 20 projects per page" do
    slug = project_types(:instalaciones).slug
    25.times { |n| Project.create!(project_type: project_types(:instalaciones), name: "Proyecto #{n}", custom_fields: {}) }

    get projects_path
    assert_response :success
    assert_select "table tbody tr", count: 20

    get projects_path, params: { sections: { slug => { page: 2 } } }
    assert_response :success
    assert_select "table tbody tr", count: 5
  end

  test "index's KPI cards and Gantt tasks count all filtered projects, not just the current page" do
    slug = project_types(:instalaciones).slug
    25.times { |n| Project.create!(project_type: project_types(:instalaciones), name: "Proyecto #{n}", custom_fields: {}) }

    get projects_path
    assert_response :success
    assert_select ".card .display-6", "25"
    assert_select "script#gantt-tasks-#{slug}" do |elements|
      tasks = JSON.parse(elements.first.text)
      assert_equal 25, tasks.size
    end
  end

  test "index shows no pagination controls when there are 20 projects or fewer" do
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get projects_path
    assert_response :success
    assert_select "ul.pagination", count: 0
  end

  test "index shows pagination controls that preserve the current section's filter" do
    slug = project_types(:instalaciones).slug
    25.times { |n| Project.create!(project_type: project_types(:instalaciones), name: "Proyecto #{n}", custom_fields: {}, status: "active") }

    get projects_path, params: { sections: { slug => { status: "active" } } }
    assert_response :success
    assert_select "ul.pagination"
    assert_select "a.page-link[href=?]", projects_path(sections: { slug => { status: "active", page: 2 } })
  end

  test "index's Etapa filter uses the configured default stage on a fresh, unfiltered load" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    stage = project.project_stages.find_by(name: "Instalación")
    stage.update!(start_date: Date.new(2026, 9, 1), end_date: Date.new(2026, 9, 10))
    stage_templates(:instalacion).update!(default_in_filter: true)
    slug = project_types(:instalaciones).slug

    get projects_path
    assert_response :success
    assert_select "select#sections_#{slug}_stage_name option[selected]", "Instalación"
    assert_select "script#gantt-tasks-#{slug}" do |elements|
      tasks = JSON.parse(elements.first.text)
      task = tasks.find { |t| t["id"] == project.id.to_s }
      assert_equal "2026-09-01", task["start"]
      assert_equal "2026-09-10", task["end"]
    end
  end

  test "index's Etapa filter doesn't apply the default when the section was explicitly filtered with Etapa left blank" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    stage_templates(:instalacion).update!(default_in_filter: true)
    slug = project_types(:instalaciones).slug

    get projects_path, params: { sections: { slug => { stage_name: "", status: "" } } }
    assert_response :success
    assert_select "script#gantt-tasks-#{slug}" do |elements|
      tasks = JSON.parse(elements.first.text)
      task = tasks.find { |t| t["id"] == project.id.to_s }
      first, last = project.gantt_window
      assert_equal first.to_s, task["start"]
      assert_equal last.to_s, task["end"]
    end
  end

  test "index without any default stage configured behaves exactly as before" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    slug = project_types(:instalaciones).slug

    get projects_path
    assert_response :success
    assert_select "script#gantt-tasks-#{slug}" do |elements|
      tasks = JSON.parse(elements.first.text)
      task = tasks.find { |t| t["id"] == project.id.to_s }
      first, last = project.gantt_window
      assert_equal first.to_s, task["start"]
      assert_equal last.to_s, task["end"]
    end
  end

  test "index shows a Quitar filtros link that explicitly blanks every field for that section" do
    slug = project_types(:instalaciones).slug
    get projects_path
    assert_response :success
    assert_select "a", text: "Quitar filtros" do |elements|
      href = elements.first["href"]
      uri = URI.parse(href)
      params = Rack::Utils.parse_nested_query(uri.query)
      assert_equal "", params["sections"][slug]["status"]
      assert_equal "", params["sections"][slug]["installer_id"]
      assert_equal "", params["sections"][slug]["stage_name"]
      assert_equal "", params["sections"][slug]["from_date"]
      assert_equal "", params["sections"][slug]["to_date"]
      assert_equal "", params["sections"][slug]["q"]
    end
  end
end
