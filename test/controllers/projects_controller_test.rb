require "test_helper"

class ProjectsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:juan) }

  test "index lists projects" do
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_type_projects_path(project_types(:instalaciones).slug)
    assert_response :success
    assert_select "body", /Torre Norte/
  end

  test "new renders one input per field_definition of the selected type" do
    get new_project_path(project_type_id: project_types(:instalaciones).id)
    assert_response :success
    assert_select "input[name=?]", "project[custom_fields][cliente]"
    assert_select "input[name=?]", "project[custom_fields][direccion]"
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
          custom_fields: { cliente: "Acme S.A.", direccion: "Av. Siempre Viva 123" }
        }
      }
    end
    project = Project.order(:id).last
    assert_redirected_to project_path(project)
    assert_equal 5, project.project_stages.count
  end

  test "create with invalid data re-renders form with error" do
    assert_no_difference("Project.count") do
      post projects_path, params: {
        project: {
          project_type_id: project_types(:instalaciones).id,
          name: "",
          custom_fields: { cliente: "Acme S.A." }
        }
      }
    end
    assert_response :unprocessable_entity
  end

  test "new prefills a shared field from the source project even when the target key has a different name" do
    other_type = ProjectType.create!(name: "Caso de Servicio", slug: "caso-de-servicio")
    FieldDefinition.create!(project_type: other_type, key: "nombre_cliente", label: "Nombre del cliente", data_type: "text", position: 1)
    association = ProjectTypeAssociation.create!(
      from_project_type: other_type, to_project_type: project_types(:instalaciones),
      label: "Caso de servicio", shared_field_mappings: [{ from: "nombre_cliente", to: "cliente" }]
    )
    source = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: { "cliente" => "Acme S.A." })

    get new_project_path(project_type_id: other_type.id, project_type_association_id: association.id, associate_with_project_id: source.id)

    assert_response :success
    assert_select "input[name=?][value=?]", "project[custom_fields][nombre_cliente]", "Acme S.A."
  end

  test "new does not prefill a mapped field when data_type differs between types" do
    other_type = ProjectType.create!(name: "Caso de Servicio", slug: "caso-de-servicio")
    FieldDefinition.create!(project_type: other_type, key: "nombre_cliente", label: "Nombre del cliente", data_type: "number", position: 1)
    association = ProjectTypeAssociation.create!(
      from_project_type: other_type, to_project_type: project_types(:instalaciones),
      label: "Caso de servicio", shared_field_mappings: [{ from: "nombre_cliente", to: "cliente" }]
    )
    source = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: { "cliente" => "Acme S.A." })

    get new_project_path(project_type_id: other_type.id, project_type_association_id: association.id, associate_with_project_id: source.id)

    assert_response :success
    assert_select "input[name=?][value=?]", "project[custom_fields][nombre_cliente]", "Acme S.A.", count: 0
  end

  test "create copies a mapped shared field from the source project when it's left blank" do
    other_type = ProjectType.create!(name: "Caso de Servicio", slug: "caso-de-servicio")
    FieldDefinition.create!(project_type: other_type, key: "nombre_cliente", label: "Nombre del cliente", data_type: "text", position: 1)
    association = ProjectTypeAssociation.create!(
      from_project_type: other_type, to_project_type: project_types(:instalaciones),
      label: "Caso de servicio", shared_field_mappings: [{ from: "nombre_cliente", to: "cliente" }]
    )
    source = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: { "cliente" => "Acme S.A." })

    assert_difference("Project.count", 1) do
      post projects_path, params: {
        project: { project_type_id: other_type.id, name: "Caso 1", custom_fields: {} },
        project_type_association_id: association.id, associate_with_project_id: source.id
      }
    end

    assert_equal "Acme S.A.", Project.order(:id).last.custom_fields["nombre_cliente"]
  end

  test "create respects a mapped shared field the user filled in themselves instead of overwriting it" do
    other_type = ProjectType.create!(name: "Caso de Servicio", slug: "caso-de-servicio")
    FieldDefinition.create!(project_type: other_type, key: "nombre_cliente", label: "Nombre del cliente", data_type: "text", position: 1)
    association = ProjectTypeAssociation.create!(
      from_project_type: other_type, to_project_type: project_types(:instalaciones),
      label: "Caso de servicio", shared_field_mappings: [{ from: "nombre_cliente", to: "cliente" }]
    )
    source = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: { "cliente" => "Acme S.A." })

    post projects_path, params: {
      project: { project_type_id: other_type.id, name: "Caso 1", custom_fields: { nombre_cliente: "Otro Cliente" } },
      project_type_association_id: association.id, associate_with_project_id: source.id
    }

    assert_equal "Otro Cliente", Project.order(:id).last.custom_fields["nombre_cliente"]
  end

  test "new prefills the project name when mapped from the source project's name" do
    other_type = ProjectType.create!(name: "Caso de Servicio", slug: "caso-de-servicio")
    association = ProjectTypeAssociation.create!(
      from_project_type: other_type, to_project_type: project_types(:instalaciones),
      label: "Caso de servicio", shared_field_mappings: [{ from: "name", to: "name" }]
    )
    source = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})

    get new_project_path(project_type_id: other_type.id, project_type_association_id: association.id, associate_with_project_id: source.id)

    assert_response :success
    assert_select "input[name=?][value=?]", "project[name]", "Torre Norte"
  end

  test "new prefills the project name from a mapped custom field on the source project" do
    other_type = ProjectType.create!(name: "Caso de Servicio", slug: "caso-de-servicio")
    association = ProjectTypeAssociation.create!(
      from_project_type: other_type, to_project_type: project_types(:instalaciones),
      label: "Caso de servicio", shared_field_mappings: [{ from: "name", to: "cliente" }]
    )
    source = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: { "cliente" => "Acme S.A." })

    get new_project_path(project_type_id: other_type.id, project_type_association_id: association.id, associate_with_project_id: source.id)

    assert_response :success
    assert_select "input[name=?][value=?]", "project[name]", "Acme S.A."
  end

  test "create copies the project name from the source project when left blank" do
    other_type = ProjectType.create!(name: "Caso de Servicio", slug: "caso-de-servicio")
    association = ProjectTypeAssociation.create!(
      from_project_type: other_type, to_project_type: project_types(:instalaciones),
      label: "Caso de servicio", shared_field_mappings: [{ from: "name", to: "name" }]
    )
    source = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})

    post projects_path, params: {
      project: { project_type_id: other_type.id, name: "", custom_fields: {} },
      project_type_association_id: association.id, associate_with_project_id: source.id
    }

    assert_equal "Torre Norte", Project.order(:id).last.name
  end

  test "new does not prefill when shared_field_mappings references a since-deleted field definition" do
    other_type = ProjectType.create!(name: "Caso de Servicio", slug: "caso-de-servicio")
    association = ProjectTypeAssociation.create!(
      from_project_type: other_type, to_project_type: project_types(:instalaciones),
      label: "Caso de servicio", shared_field_mappings: [{ from: "nombre_cliente", to: "cliente" }]
    )
    source = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: { "cliente" => "Acme S.A." })

    get new_project_path(project_type_id: other_type.id, project_type_association_id: association.id, associate_with_project_id: source.id)

    assert_response :success
  end

  test "new without associate_with_project_id renders an empty form as before" do
    get new_project_path(project_type_id: project_types(:instalaciones).id)
    assert_response :success
    assert_select "input[name=?]", "project[custom_fields][cliente]", count: 1
    assert_select "input[name=?][value]", "project[custom_fields][cliente]", count: 0
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
    get project_type_projects_path(project_types(:instalaciones).slug)
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
    get project_type_projects_path(project_types(:instalaciones).slug)
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
    project = Project.create!(
      project_type: project_types(:instalaciones), name: "Torre Norte",
      custom_fields: { cliente: "Acme S.A.", direccion: "Av. Siempre Viva 123" }
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

  test "show renders the bitácora with existing entries and an add form" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    LogEntry.create!(project: project, user: users(:juan), log_entry_type: log_entry_types(:nota), body: "Nota visible en la bitácora")

    get project_path(project)

    assert_response :success
    assert_select "body", /Nota visible en la bitácora/
    assert_select "form[action=?]", project_log_entries_path(project)
  end

  test "index shows an edit link for each project" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_type_projects_path(project_types(:instalaciones).slug)
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

  test "show's Gantt has a legend naming each stage_template's color" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    stage_templates(:produccion).update!(color: "#ff0000")

    get project_path(project)
    assert_response :success
    assert_select ".gantt-legend span", text: /Producción/
  end

  test "show's Gantt legend labels a stage with no stage_template as Sin subproceso" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    project.project_stages.first.update!(stage_template: nil)

    get project_path(project)
    assert_response :success
    assert_select ".gantt-legend span", text: /Sin subproceso/
  end

  test "show's Responsables assignment form only offers responsibles enabled for this project's type" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    other_type = ProjectType.create!(name: "Mantenimiento", slug: "mantenimiento")
    not_enabled = Responsible.create!(name: "No Habilitado")
    ResponsibleProjectType.create!(responsible: not_enabled, project_type: other_type)

    get project_path(project)
    assert_response :success
    assert_select "select[name=?] option", "project_responsible[responsible_id]", text: "Ana Gómez"
    assert_select "select[name=?] option", "project_responsible[responsible_id]", text: "No Habilitado", count: 0
  end

  test "index's Gantt legend appears only when a responsible type is selected" do
    slug = project_types(:instalaciones).slug
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    ProjectResponsible.create!(project: project, responsible: responsibles(:ana_gomez), responsible_type: responsible_types(:instalador))

    get project_type_projects_path(slug)
    assert_response :success
    assert_select ".gantt-legend", count: 0

    get project_type_projects_path(slug), params: { responsible_type_id: responsible_types(:instalador).id }
    assert_response :success
    assert_select ".gantt-legend span", text: /Ana Gómez/
  end

  test "index shows one Gantt task per project by default" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_type_projects_path(project_types(:instalaciones).slug)
    assert_response :success
    assert_select "script#gantt-tasks-#{project_types(:instalaciones).slug}", text: /#{project.name}/
  end

  test "index configures the Gantt in Spanish with native readonly options" do
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_type_projects_path(project_types(:instalaciones).slug)
    assert_response :success
    assert_match(/language:\s*"es"/, response.body)
    assert_match(/readonly_dates:\s*true/, response.body)
    assert_match(/readonly_progress:\s*true/, response.body)
  end

  test "index's Gantt tasks include status, progress, and every responsible for the hover popup" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {}, status: "active")
    ProjectResponsible.create!(project: project, responsible: responsibles(:ana_gomez), responsible_type: responsible_types(:instalador))
    ProjectResponsible.create!(project: project, responsible: responsibles(:pedro_responsable), responsible_type: responsible_types(:disenador))
    slug = project_types(:instalaciones).slug

    get project_type_projects_path(slug)
    assert_response :success
    assert_select "script#gantt-tasks-#{slug}" do |elements|
      task = JSON.parse(elements.first.text).find { |t| t["id"] == project.id.to_s }
      assert_equal "Activo", task["status_label"]
      assert_equal "Sin iniciar", task["progress_status_label"]
      names = task["responsibles"].map { |r| [r["type"], r["name"]] }
      assert_includes names, ["Instalador Fixture", "Ana Gómez"]
      assert_includes names, ["Diseñador Fixture", "Pedro Instalador"]
    end
  end

  test "index's Gantt popup renders a styled tooltip instead of the default popup" do
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_type_projects_path(project_types(:instalaciones).slug)
    assert_response :success
    assert_match(/popup:\s*function\s*\(ctx\)/, response.body)
    assert_match(/popup_on:\s*"hover"/, response.body)
    assert_no_match(/popup:\s*false/, response.body)
  end

  test "index's Gantt click handler is wired via the on_click constructor option, not gantt.on" do
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_type_projects_path(project_types(:instalaciones).slug)
    assert_response :success
    assert_match(/on_click:\s*function\s*\(task\)\s*\{\s*window\.location\s*=\s*task\.edit_url;\s*\}/, response.body)
    assert_no_match(/gantt\.on\(/, response.body)
  end

  test "index's Gantt overrides the progress-bar fill for visibility against custom bar colors" do
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_type_projects_path(project_types(:instalaciones).slug)
    assert_response :success
    assert_match(/\.gantt \.bar-progress \{\s*fill:\s*rgba\(0,\s*0,\s*0,\s*0\.25\);?\s*\}/, response.body)
  end

  test "index configures the Gantt with a fixed container height instead of manual scroll CSS" do
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_type_projects_path(project_types(:instalaciones).slug)
    assert_response :success
    slug = project_types(:instalaciones).slug
    assert_select "#gantt-#{slug}[style]", count: 0
    assert_match(/container_height:\s*630/, response.body)
  end

  test "index loads frappe-gantt 1.2.2" do
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_type_projects_path(project_types(:instalaciones).slug)
    assert_response :success
    assert_match(%r{frappe-gantt@1\.2\.2/dist/frappe-gantt\.css}, response.body)
    assert_match(%r{frappe-gantt@1\.2\.2/dist/frappe-gantt\.umd\.js}, response.body)
    assert_no_match(/frappe-gantt@0\.6\.1/, response.body)
  end

  test "index shows Día/Semana/Mes view-mode buttons for the Gantt" do
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_type_projects_path(project_types(:instalaciones).slug)
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

    get project_type_projects_path(slug), params: { stage_name: "Instalación", status: "" }
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

    get project_type_projects_path(slug), params: { stage_name: "Etapa Inexistente", status: "" }
    assert_response :success
    assert_select "script#gantt-tasks-#{slug}" do |elements|
      tasks = JSON.parse(elements.first.text)
      assert_nil tasks.find { |t| t["id"] == project.id.to_s }
    end
  end

  test "index's Gantt without a stage filter still shows each project's full range" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    slug = project_types(:instalaciones).slug
    get project_type_projects_path(slug)
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

    get project_type_projects_path(slug), params: { stage_name: "Etapa Inexistente", status: "" }
    assert_response :success
    assert_select ".card .display-6", "1"
    assert_select "a[href=?]", project_path(project)
  end

  test "index without a slug redirects to the first project type's tab" do
    get projects_path
    assert_redirected_to project_type_projects_path(ProjectType.first.slug)
  end

  test "index with an unknown slug redirects to the first project type's tab" do
    get project_type_projects_path("no-existe")
    assert_redirected_to project_type_projects_path(ProjectType.first.slug)
  end

  test "index with no ProjectType configured at all shows a message instead of erroring" do
    ProjectType.destroy_all
    get projects_path
    assert_response :success
    assert_select "body", /No hay tipos de proyecto configurados todavía/
  end

  test "index shows a tab for every project type, with the current one active" do
    other_type = ProjectType.create!(name: "Mantenimiento", slug: "mantenimiento")
    get project_type_projects_path(project_types(:instalaciones).slug)
    assert_response :success
    assert_select "a.nav-link.active", text: project_types(:instalaciones).name
    assert_select "a.nav-link", text: other_type.name
  end

  test "index's Etapa dropdown only lists stages belonging to that section's own project type" do
    other_type = ProjectType.create!(name: "Mantenimiento", slug: "mantenimiento")
    StageTemplate.create!(project_type: other_type, name: "Etapa De Otro Tipo", position: 1)

    get project_type_projects_path(project_types(:instalaciones).slug)
    assert_response :success
    assert_select "select#stage_name option", text: "Instalación"
    assert_select "select#stage_name option", text: "Etapa De Otro Tipo", count: 0
  end

  test "index shows an Etapa dropdown with the distinct stage template names" do
    get project_type_projects_path(project_types(:instalaciones).slug)
    assert_response :success
    assert_select "select#stage_name option", text: "Instalación"
    assert_select "select#stage_name option", text: "Producción"
  end

  test "index filters by status" do
    slug = project_types(:instalaciones).slug
    torre = Project.create!(
      project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {}, status: "active"
    )
    vieja = Project.create!(
      project_type: project_types(:instalaciones), name: "Torre Vieja", custom_fields: {}, status: "archived"
    )

    get project_type_projects_path(slug), params: { status: "archived" }
    assert_response :success
    assert_match(/#{vieja.name}/, response.body)
    assert_no_match(/#{torre.name}/, response.body)
  end

  test "index filters by responsible" do
    slug = project_types(:instalaciones).slug
    con_ana = Project.create!(project_type: project_types(:instalaciones), name: "Con Ana", custom_fields: {})
    ProjectResponsible.create!(project: con_ana, responsible: responsibles(:ana_gomez), responsible_type: responsible_types(:instalador))
    otro_responsable = Responsible.create!(name: "Otro")
    ResponsibleProjectType.create!(responsible: otro_responsable, project_type: project_types(:instalaciones))
    con_otro = Project.create!(project_type: project_types(:instalaciones), name: "Con Otro", custom_fields: {})
    ProjectResponsible.create!(project: con_otro, responsible: otro_responsable, responsible_type: responsible_types(:instalador))

    get project_type_projects_path(slug), params: {
      responsible_type_id: responsible_types(:instalador).id, responsible_id: responsibles(:ana_gomez).id
    }
    assert_response :success
    assert_match(/#{con_ana.name}/, response.body)
    assert_no_match(/#{con_otro.name}/, response.body)
  end

  test "index filters by Sin asignar for a chosen type" do
    slug = project_types(:instalaciones).slug
    sin_asignar = Project.create!(project_type: project_types(:instalaciones), name: "Sin Asignar", custom_fields: {})
    con_asignacion = Project.create!(project_type: project_types(:instalaciones), name: "Con Asignación", custom_fields: {})
    ProjectResponsible.create!(project: con_asignacion, responsible: responsibles(:ana_gomez), responsible_type: responsible_types(:instalador))

    get project_type_projects_path(slug), params: {
      responsible_type_id: responsible_types(:instalador).id, responsible_id: "none"
    }
    assert_response :success
    assert_match(/#{sin_asignar.name}/, response.body)
    assert_no_match(/#{con_asignacion.name}/, response.body)
  end

  test "index shows a Tipo de responsable and Responsable filter" do
    get project_type_projects_path(project_types(:instalaciones).slug)
    assert_response :success
    assert_select "select#responsible_type_id"
    assert_select "select#responsible_id"
  end

  test "index shows a message and no Gantt when no projects match the filters" do
    slug = project_types(:instalaciones).slug
    get project_type_projects_path(slug), params: { status: "nonexistent-status" }
    assert_response :success
    assert_select "body", /No hay proyectos con estos filtros/
    assert_select "#gantt-#{slug}", count: 0
  end

  test "index excludes archived projects by default" do
    Project.create!(project_type: project_types(:instalaciones), name: "Activo", custom_fields: {})
    Project.create!(
      project_type: project_types(:instalaciones), name: "Archivado", custom_fields: {}, status: "archived"
    )
    get project_type_projects_path(project_types(:instalaciones).slug)
    assert_response :success
    assert_select "body", /Activo/
    assert_select "body", text: /Archivado/, count: 0
  end

  test "index shows an archive button for each project" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_type_projects_path(project_types(:instalaciones).slug)
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
    get project_type_projects_path(project_types(:instalaciones).slug)
    assert_response :success
    assert_select "span.badge.bg-success", "Activo"
    assert_select "body", text: /\bactive\b/, count: 0
  end

  test "index shows Spanish labels in the status filter while keeping English values" do
    Project.create!(
      project_type: project_types(:instalaciones), name: "Torre Vieja", custom_fields: {}, status: "archived"
    )
    get project_type_projects_path(project_types(:instalaciones).slug)
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

  test "tracker filters by responsible" do
    con_ana = Project.create!(project_type: project_types(:instalaciones), name: "Con Ana", custom_fields: {})
    ProjectResponsible.create!(project: con_ana, responsible: responsibles(:ana_gomez), responsible_type: responsible_types(:instalador))
    otro_responsable = Responsible.create!(name: "Otro")
    ResponsibleProjectType.create!(responsible: otro_responsable, project_type: project_types(:instalaciones))
    con_otro = Project.create!(project_type: project_types(:instalaciones), name: "Con Otro", custom_fields: {})
    ProjectResponsible.create!(project: con_otro, responsible: otro_responsable, responsible_type: responsible_types(:instalador))

    get tracker_projects_path, params: { responsible_type_id: responsible_types(:instalador).id, responsible_id: responsibles(:ana_gomez).id }
    assert_response :success
    assert_match(/#{con_ana.name}/, response.body)
    assert_no_match(/#{con_otro.name}/, response.body)
  end

  test "tracker's responsible-type filter uses the configured default on a fresh, unfiltered load" do
    responsible_types(:instalador).update!(default_in_filter: true)

    get tracker_projects_path(project_type_id: project_types(:instalaciones).id)
    assert_response :success
    assert_select "select#responsible_type_id option[selected]", "Instalador Fixture"
  end

  test "tracker's responsible-type filter doesn't apply the default when explicitly left blank" do
    responsible_types(:instalador).update!(default_in_filter: true)

    get tracker_projects_path(project_type_id: project_types(:instalaciones).id, responsible_type_id: "")
    assert_response :success
    assert_select "select#responsible_type_id option[selected]", false
  end

  test "tracker's responsible-type filter respects an explicitly chosen type over the default" do
    responsible_types(:instalador).update!(default_in_filter: true)

    get tracker_projects_path(project_type_id: project_types(:instalaciones).id, responsible_type_id: responsible_types(:disenador).id)
    assert_response :success
    assert_select "select#responsible_type_id option[selected]", "Diseñador Fixture"
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
    assert_select ".card-header", /Instalaciones/
    assert_select ".card form"
    assert_select "a[href=?]", projects_path, text: "Cancelar"
  end

  test "edit shows the project name in the title, wraps the form in a card, and links Cancelar to the project" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get edit_project_path(project)
    assert_response :success
    assert_select ".card-header", /Torre Norte/
    assert_select ".card form"
    assert_select "a[href=?]", project_path(project), text: "Cancelar"
  end

  test "index's filter card has a Filtros title" do
    get project_type_projects_path(project_types(:instalaciones).slug)
    assert_response :success
    assert_select ".card-header", "Filtros"
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

  test "index shows a Nuevo proyecto link for the current project type" do
    ProjectType.create!(name: "Mantenimiento", slug: "mantenimiento")
    get project_type_projects_path(project_types(:instalaciones).slug)
    assert_response :success
    assert_select "a.btn[href=?]", new_project_path(project_type_id: project_types(:instalaciones).id), text: "Nuevo proyecto"
  end

  test "index shows KPI cards for total, overdue, and finalizado projects" do
    Project.create!(project_type: project_types(:instalaciones), name: "Activo", custom_fields: {})
    vencido = Project.create!(project_type: project_types(:instalaciones), name: "Vencido", custom_fields: {})
    vencido.project_stages.order(:id).first.update!(end_date: Date.current - 1.day, progress_percent: 50)
    finalizado = Project.create!(project_type: project_types(:instalaciones), name: "Finalizado", custom_fields: {})
    finalizado.project_stages.each { |stage| stage.update!(progress_percent: 100) }

    get project_type_projects_path(project_types(:instalaciones).slug)
    assert_response :success
    assert_select ".card .display-6", "3"
    assert_select ".card .display-6.text-danger", "1"
    assert_select ".card .display-6.text-success", "1"
  end

  test "index shows progress-status and overdue badges in the table" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    project.project_stages.order(:id).first.update!(end_date: Date.current - 1.day, progress_percent: 40)

    get project_type_projects_path(project_types(:instalaciones).slug)
    assert_response :success
    assert_select "table span.badge.bg-info", "Iniciado"
    assert_select "table span.badge.bg-danger", "Vencido"
  end

  test "index wraps the Gantt and the table in cards" do
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_type_projects_path(project_types(:instalaciones).slug)
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

  test "bulk_assign_responsible assigns the responsible to every selected project at the project level" do
    proyecto_a = Project.create!(project_type: project_types(:instalaciones), name: "Proyecto A", custom_fields: {})
    proyecto_b = Project.create!(project_type: project_types(:instalaciones), name: "Proyecto B", custom_fields: {})

    patch bulk_assign_responsible_projects_path, params: {
      responsible_type_id: responsible_types(:instalador).id, responsible_id: responsibles(:ana_gomez).id,
      project_ids: [proyecto_a.id, proyecto_b.id], project_type_slug: project_types(:instalaciones).slug
    }

    assert_redirected_to project_type_projects_path(project_types(:instalaciones).slug)
    assert proyecto_a.reload.project_responsibles.exists?(responsible: responsibles(:ana_gomez), responsible_type: responsible_types(:instalador))
    assert proyecto_b.reload.project_responsibles.exists?(responsible: responsibles(:ana_gomez), responsible_type: responsible_types(:instalador))
    follow_redirect!
    assert_match(/Responsable asignado a 2 proyecto\(s\)/, response.body)
  end

  test "bulk_assign_responsible replaces an existing project-wide assignment of the same type" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Proyecto A", custom_fields: {})
    ProjectResponsible.create!(project: project, responsible: responsibles(:ana_gomez), responsible_type: responsible_types(:instalador))
    otro_responsable = Responsible.create!(name: "Otro")
    ResponsibleProjectType.create!(responsible: otro_responsable, project_type: project_types(:instalaciones))

    patch bulk_assign_responsible_projects_path, params: {
      responsible_type_id: responsible_types(:instalador).id, responsible_id: otro_responsable.id, project_ids: [project.id]
    }

    assert_equal [otro_responsable], project.reload.project_responsibles.where(responsible_type: responsible_types(:instalador), project_stage: nil).map(&:responsible)
  end

  test "bulk_assign_responsible without a type or responsible chosen does nothing and redirects with an alert" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Proyecto A", custom_fields: {})

    patch bulk_assign_responsible_projects_path, params: {
      responsible_type_id: "", responsible_id: "", project_ids: [project.id], project_type_slug: project_types(:instalaciones).slug
    }

    assert_redirected_to project_type_projects_path(project_types(:instalaciones).slug)
    assert_equal [], project.reload.project_responsibles.to_a
    follow_redirect!
    assert_match(/Elegí un tipo, un responsable y al menos un proyecto/, response.body)
  end

  test "index renders a bulk-assign form with a checkbox per project, not nested inside another form" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    slug = project_types(:instalaciones).slug
    get project_type_projects_path(slug)
    assert_response :success

    assert_select "form#bulk-assign-form-#{slug}[action=?]", bulk_assign_responsible_projects_path
    assert_select "form#bulk-assign-form-#{slug} select[name=?]", "responsible_type_id"
    assert_select "form#bulk-assign-form-#{slug} input[type=submit][value=?]", "Asignar"
    assert_select "input[type=checkbox][name=?][form=bulk-assign-form-#{slug}]", "project_ids[]", value: project.id.to_s

    doc = Nokogiri::HTML5(response.body)
    bulk_form = doc.at_css("#bulk-assign-form-#{slug}")
    assert_nil bulk_form.at_css("form"), "the archive button's form must not be nested inside the bulk-assign form"
  end

  test "index's bulk-assign selector only offers responsibles enabled for this project type" do
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    other_type = ProjectType.create!(name: "Mantenimiento", slug: "mantenimiento")
    not_enabled = Responsible.create!(name: "No Habilitado")
    ResponsibleProjectType.create!(responsible: not_enabled, project_type: other_type)

    get project_type_projects_path(project_types(:instalaciones).slug)
    assert_response :success
    assert_select "select#bulk-assign-responsible-select-#{project_types(:instalaciones).slug} option", text: "Ana Gómez"
    assert_select "select#bulk-assign-responsible-select-#{project_types(:instalaciones).slug} option", text: "No Habilitado", count: 0
  end

  test "index's select-all checkbox toggles every project checkbox via JS" do
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_type_projects_path(project_types(:instalaciones).slug)
    assert_response :success
    slug = project_types(:instalaciones).slug
    assert_select "input#select-all-projects-#{slug}[type=checkbox]"
    assert_match(/select-all-projects-#{slug}/, response.body)
    assert_match(/project_ids\[\]/, response.body)
  end

  test "index's pagination Anterior link points to the previous page, not itself" do
    slug = project_types(:instalaciones).slug
    25.times { |n| Project.create!(project_type: project_types(:instalaciones), name: "Proyecto #{n}", custom_fields: {}) }
    get project_type_projects_path(slug), params: { page: 2 }
    assert_response :success
    assert_select "a.page-link[href=?]", project_type_projects_path(slug, page: 1)
  end

  test "index filters by a Desde/Hasta date range that overlaps a project's stages" do
    slug = project_types(:instalaciones).slug
    dentro = Project.create!(project_type: project_types(:instalaciones), name: "Dentro del Rango", custom_fields: {})
    dentro.project_stages.order(:id).first.update!(start_date: Date.new(2026, 3, 1), end_date: Date.new(2026, 3, 10))

    fuera = Project.create!(project_type: project_types(:instalaciones), name: "Fuera del Rango", custom_fields: {})
    fuera.project_stages.each { |s| s.update!(start_date: Date.new(2026, 6, 1), end_date: Date.new(2026, 6, 10)) }

    get project_type_projects_path(slug), params: { from_date: "2026-02-01", to_date: "2026-04-01" }
    assert_response :success
    assert_match(/#{dentro.name}/, response.body)
    assert_no_match(/#{fuera.name}/, response.body)
  end

  test "index without from_date or to_date shows all projects allowed by the other filters" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_type_projects_path(project_types(:instalaciones).slug)
    assert_response :success
    assert_match(/#{project.name}/, response.body)
  end

  test "index shows Desde and Hasta date fields in the filter form" do
    get project_type_projects_path(project_types(:instalaciones).slug)
    assert_response :success
    assert_select "input[type=date][name=?]", "from_date"
    assert_select "input[type=date][name=?]", "to_date"
  end

  test "index's Desde/Hasta filter always shows projects with no dated stages, regardless of the range" do
    slug = project_types(:instalaciones).slug
    sin_fechas = Project.create!(project_type: project_types(:instalaciones), name: "Sin Fechas", custom_fields: {})
    fuera = Project.create!(project_type: project_types(:instalaciones), name: "Fuera del Rango", custom_fields: {})
    fuera.project_stages.each { |s| s.update!(start_date: Date.new(2026, 6, 1), end_date: Date.new(2026, 6, 10)) }

    get project_type_projects_path(slug), params: { from_date: "2026-02-01", to_date: "2026-04-01" }
    assert_response :success
    assert_match(/#{sin_fechas.name}/, response.body)
    assert_no_match(/#{fuera.name}/, response.body)
  end

  test "index's q filter matches a project by name" do
    slug = project_types(:instalaciones).slug
    match = Project.create!(project_type: project_types(:instalaciones), name: "Torre del Bosque", custom_fields: {})
    other = Project.create!(project_type: project_types(:instalaciones), name: "Otro Proyecto", custom_fields: {})

    get project_type_projects_path(slug), params: { q: "Bosque" }
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

    get project_type_projects_path(slug), params: { q: "Acme" }
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

    get project_type_projects_path(slug), params: { q: "constructora grande" }
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

    get project_type_projects_path(slug), params: { q: "Torre Norte", status: "active" }
    assert_response :success
    assert_select "a[href=?]", project_path(match)
    assert_select "a[href=?]", project_path(otro_estado), count: 0
  end

  test "index shows no results when q doesn't match anything" do
    slug = project_types(:instalaciones).slug
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_type_projects_path(slug), params: { q: "esto-no-existe-en-ningun-proyecto" }
    assert_response :success
    assert_select "body", /No hay proyectos con estos filtros/
  end

  test "index shows the q search field in the filter form" do
    get project_type_projects_path(project_types(:instalaciones).slug)
    assert_response :success
    assert_select "input[type=text][name=?]", "q"
  end

  test "index paginates the Listado table at 20 projects per page" do
    slug = project_types(:instalaciones).slug
    25.times { |n| Project.create!(project_type: project_types(:instalaciones), name: "Proyecto #{n}", custom_fields: {}) }

    get project_type_projects_path(slug)
    assert_response :success
    assert_select "table tbody tr", count: 20

    get project_type_projects_path(slug), params: { page: 2 }
    assert_response :success
    assert_select "table tbody tr", count: 5
  end

  test "index's KPI cards and Gantt tasks count all filtered projects, not just the current page" do
    slug = project_types(:instalaciones).slug
    25.times { |n| Project.create!(project_type: project_types(:instalaciones), name: "Proyecto #{n}", custom_fields: {}) }

    get project_type_projects_path(slug)
    assert_response :success
    assert_select ".card .display-6", "25"
    assert_select "script#gantt-tasks-#{slug}" do |elements|
      tasks = JSON.parse(elements.first.text)
      assert_equal 25, tasks.size
    end
  end

  test "index shows no pagination controls when there are 20 projects or fewer" do
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_type_projects_path(project_types(:instalaciones).slug)
    assert_response :success
    assert_select "ul.pagination", count: 0
  end

  test "index shows pagination controls that preserve the current section's filter" do
    slug = project_types(:instalaciones).slug
    25.times { |n| Project.create!(project_type: project_types(:instalaciones), name: "Proyecto #{n}", custom_fields: {}, status: "active") }

    get project_type_projects_path(slug), params: { status: "active" }
    assert_response :success
    assert_select "ul.pagination"
    assert_select "a.page-link[href=?]", project_type_projects_path(slug, status: "active", page: 2)
  end

  test "index's Etapa filter uses the configured default stage on a fresh, unfiltered load" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    stage = project.project_stages.find_by(name: "Instalación")
    stage.update!(start_date: Date.new(2026, 9, 1), end_date: Date.new(2026, 9, 10))
    stage_templates(:instalacion).update!(default_in_filter: true)
    slug = project_types(:instalaciones).slug

    get project_type_projects_path(slug)
    assert_response :success
    assert_select "select#stage_name option[selected]", "Instalación"
    assert_select "script#gantt-tasks-#{slug}" do |elements|
      tasks = JSON.parse(elements.first.text)
      task = tasks.find { |t| t["id"] == project.id.to_s }
      assert_equal "2026-09-01", task["start"]
      assert_equal "2026-09-10", task["end"]
    end
  end

  test "index's responsible-type filter uses the configured default on a fresh, unfiltered load" do
    responsible_types(:instalador).update!(default_in_filter: true)
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    ProjectResponsible.create!(project: project, responsible: responsibles(:ana_gomez), responsible_type: responsible_types(:instalador))
    slug = project_types(:instalaciones).slug

    get project_type_projects_path(slug)
    assert_response :success
    assert_select "select#responsible_type_id option[selected]", "Instalador Fixture"
  end

  test "index's responsible-type filter doesn't apply the default when the section was explicitly filtered with it left blank" do
    responsible_types(:instalador).update!(default_in_filter: true)
    slug = project_types(:instalaciones).slug

    get project_type_projects_path(slug), params: { responsible_type_id: "", status: "" }
    assert_response :success
    assert_select "select#responsible_type_id option[selected]", false
  end

  test "index's responsible-type filter respects an explicitly chosen type over the default" do
    responsible_types(:instalador).update!(default_in_filter: true)
    slug = project_types(:instalaciones).slug

    get project_type_projects_path(slug), params: { responsible_type_id: responsible_types(:disenador).id, status: "" }
    assert_response :success
    assert_select "select#responsible_type_id option[selected]", "Diseñador Fixture"
  end

  test "index's Etapa filter doesn't apply the default when the section was explicitly filtered with Etapa left blank" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    stage_templates(:instalacion).update!(default_in_filter: true)
    slug = project_types(:instalaciones).slug

    get project_type_projects_path(slug), params: { stage_name: "", status: "" }
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

    get project_type_projects_path(slug)
    assert_response :success
    assert_select "script#gantt-tasks-#{slug}" do |elements|
      tasks = JSON.parse(elements.first.text)
      task = tasks.find { |t| t["id"] == project.id.to_s }
      first, last = project.gantt_window
      assert_equal first.to_s, task["start"]
      assert_equal last.to_s, task["end"]
    end
  end

  test "index shows a Quitar filtros link that points at the bare tab URL" do
    slug = project_types(:instalaciones).slug
    get project_type_projects_path(slug), params: { status: "archived", q: "algo" }
    assert_response :success
    assert_select "a[href=?]", project_type_projects_path(slug), text: "Quitar filtros"
  end

  test "updating a project via the controller records the signed-in user as whodunnit" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    patch project_path(project), params: { project: { name: "Torre Norte 2" } }
    assert_equal users(:juan).id.to_s, project.versions.last.whodunnit
  end

  test "show renders the historial de cambios after an update" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    PaperTrail.request(whodunnit: users(:juan).id.to_s) do
      project.update!(name: "Torre Norte Renovada")
    end

    get project_path(project)

    assert_response :success
    assert_select ".card-header", text: "Historial de cambios"
    assert_select ".card .list-group-item", /Nombre/ do
      assert_select "div.text-muted", /Torre Norte →/
      assert_select "div.text-muted", /Torre Norte Renovada/
    end
  end

  test "show's historial de cambios includes stage version changes, prefixed with the stage name" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    stage = project.project_stages.find_by(name: "Producción")
    PaperTrail.request(whodunnit: users(:juan).id.to_s) do
      stage.update!(progress_percent: 50)
    end

    get project_path(project)

    assert_response :success
    assert_select ".card .list-group-item", /\(Etapa: Producción\)/ do
      assert_select "div.text-muted", /Porcentaje de avance/
    end
  end

  test "show renders well-formed historial for a project with only a create version" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})

    get project_path(project)

    assert_response :success
    assert_select ".list-group-item.small", minimum: 1 do |elements|
      elements.each { |element| assert_match(/Creado/, element.text) }
    end
    assert_equal @response.body.scan(/<li[ >]/).count, @response.body.scan("</li>").count
  end

  test "index only lists projects visible to a visor" do
    visible = Project.create!(project_type: project_types(:instalaciones), name: "Torre Visible", custom_fields: {})
    hidden = Project.create!(project_type: project_types(:instalaciones), name: "Torre Oculta", custom_fields: {})
    ProjectAccess.create!(user: users(:maria), project: visible)

    sign_in users(:maria)
    get project_type_projects_path(project_types(:instalaciones).slug)

    assert_response :success
    assert_select "body", /Torre Visible/
    assert_select "body", text: /Torre Oculta/, count: 0
  end

  test "show redirects a visor without access to the project" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})

    sign_in users(:maria)
    get project_path(project)

    assert_redirected_to projects_path
  end

  test "show allows a visor with access, but hides edit controls" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    ProjectAccess.create!(user: users(:maria), project: project)

    sign_in users(:maria)
    get project_path(project)

    assert_response :success
    assert_select "a[href=?]", edit_project_path(project), count: 0
  end

  test "edit redirects a gerente without edit access to the project" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})

    sign_in users(:carla)
    get edit_project_path(project)

    assert_redirected_to projects_path
  end

  test "edit allows a gerente with edit access" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    ProjectAccess.create!(user: users(:carla), project: project, can_edit: true)

    sign_in users(:carla)
    get edit_project_path(project)

    assert_response :success
  end

  test "new and create are blocked for a visor" do
    sign_in users(:maria)
    get new_project_path(project_type_id: project_types(:instalaciones).id)
    assert_redirected_to projects_path

    assert_no_difference("Project.count") do
      post projects_path, params: { project: { project_type_id: project_types(:instalaciones).id, name: "Torre Norte", custom_fields: {} } }
    end
  end

  test "create as a gerente automatically grants the creator edit access" do
    sign_in users(:carla)
    post projects_path, params: {
      project: { project_type_id: project_types(:instalaciones).id, name: "Torre Nueva", custom_fields: {} }
    }

    project = Project.find_by(name: "Torre Nueva")
    assert users(:carla).can_edit_project?(project)
  end

  test "bulk_assign_responsible only updates projects the gerente can edit" do
    editable = Project.create!(project_type: project_types(:instalaciones), name: "Torre Editable", custom_fields: {})
    not_editable = Project.create!(project_type: project_types(:instalaciones), name: "Torre No Editable", custom_fields: {})
    ProjectAccess.create!(user: users(:carla), project: editable, can_edit: true)

    sign_in users(:carla)
    patch bulk_assign_responsible_projects_path, params: {
      project_ids: [editable.id, not_editable.id],
      responsible_type_id: responsible_types(:instalador).id, responsible_id: responsibles(:ana_gomez).id
    }

    assert editable.reload.project_responsibles.exists?(responsible: responsibles(:ana_gomez), responsible_type: responsible_types(:instalador))
    assert_not not_editable.reload.project_responsibles.exists?(responsible: responsibles(:ana_gomez), responsible_type: responsible_types(:instalador))
  end

  test "responsable can update progress_percent on an assigned stage via the project PATCH" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    stage = project.project_stages.first
    responsable = users(:pedro)
    ProjectResponsible.create!(project: project, responsible: responsable.responsible, responsible_type: responsible_types(:instalador), project_stage: stage)
    sign_in responsable

    patch project_path(project), params: {
      project: { project_stages_attributes: { "0" => { id: stage.id, progress_percent: 55 } } }
    }

    assert_redirected_to project_path(project)
    assert_equal 55, stage.reload.progress_percent
  end

  test "responsable cannot update a stage they are not assigned to" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    stages = project.project_stages.order(:id).to_a
    assigned_stage, other_stage = stages[0], stages[1]
    responsable = users(:pedro)
    ProjectResponsible.create!(project: project, responsible: responsable.responsible, responsible_type: responsible_types(:instalador), project_stage: assigned_stage)
    sign_in responsable

    patch project_path(project), params: {
      project: { project_stages_attributes: { "0" => { id: other_stage.id, progress_percent: 90 } } }
    }

    assert_equal 0, other_stage.reload.progress_percent
  end

  test "responsable cannot change the project name via the project PATCH" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    stage = project.project_stages.first
    responsable = users(:pedro)
    ProjectResponsible.create!(project: project, responsible: responsable.responsible, responsible_type: responsible_types(:instalador), project_stage: stage)
    sign_in responsable

    patch project_path(project), params: {
      project: { name: "Nombre Hackeado", project_stages_attributes: { "0" => { id: stage.id, progress_percent: 10 } } }
    }

    assert_equal "Torre Norte", project.reload.name
  end

  test "responsable with no assignment on the project cannot PATCH it at all" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    sign_in users(:pedro)

    patch project_path(project), params: { project: { name: "Nombre Hackeado" } }

    assert_redirected_to projects_path
    assert_equal "Torre Norte", project.reload.name
  end

  test "responsable with a project-wide assignment sees an editable row for every stage on show" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    responsable = users(:pedro)
    ProjectResponsible.create!(project: project, responsible: responsable.responsible, responsible_type: responsible_types(:instalador))
    sign_in responsable

    get project_path(project)
    assert_response :success
    project.project_stages.each do |stage|
      assert_select "input[name=?]", "project[project_stages_attributes][#{stage.id}][progress_percent]"
    end
  end

  test "new/create is reachable by an assigned responsable when the association allows it, and links to the target project" do
    other_type = ProjectType.create!(name: "Caso de Servicio", slug: "caso-de-servicio")
    target = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    responsable = users(:pedro)
    ProjectResponsible.create!(project: target, responsible: responsable.responsible, responsible_type: responsible_types(:instalador))
    association = ProjectTypeAssociation.create!(from_project_type: other_type, to_project_type: project_types(:instalaciones), label: "Caso de servicio", responsables_can_create: true)
    sign_in responsable

    get new_project_path(project_type_id: other_type.id, project_type_association_id: association.id, associate_with_project_id: target.id)
    assert_response :success

    assert_difference("Project.count", 1) do
      post projects_path, params: {
        project: { project_type_id: other_type.id, name: "Ticket 1", custom_fields: {} },
        project_type_association_id: association.id, associate_with_project_id: target.id
      }
    end

    created = Project.order(:id).last
    assert_redirected_to project_path(target)
    assert ProjectAssociation.exists?(from_project: created, to_project: target, project_type_association: association)
  end

  test "new/create rejects a responsable when the association doesn't allow responsables to create" do
    other_type = ProjectType.create!(name: "Caso de Servicio", slug: "caso-de-servicio")
    target = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    responsable = users(:pedro)
    ProjectResponsible.create!(project: target, responsible: responsable.responsible, responsible_type: responsible_types(:instalador))
    association = ProjectTypeAssociation.create!(from_project_type: other_type, to_project_type: project_types(:instalaciones), label: "Caso de servicio")
    sign_in responsable

    get new_project_path(project_type_id: other_type.id, project_type_association_id: association.id, associate_with_project_id: target.id)
    assert_redirected_to projects_path
  end

  test "create as admin without association context still creates a standalone project" do
    assert_difference("Project.count", 1) do
      post projects_path, params: {
        project: { project_type_id: project_types(:instalaciones).id, name: "Torre Sur", custom_fields: {} }
      }
    end
    created = Project.order(:id).last
    assert_redirected_to project_path(created)
  end

  test "show's link-existing-project form tags each option with its project type, for JS filtering" do
    other_type = ProjectType.create!(name: "Caso de Servicio", slug: "caso-de-servicio")
    association = ProjectTypeAssociation.create!(from_project_type: other_type, to_project_type: project_types(:instalaciones), label: "Caso de servicio")
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    caso = Project.create!(project_type: other_type, name: "Ticket 1", custom_fields: {})

    get project_path(project)
    assert_response :success
    assert_select "select#project_association_project_type_association_id option[value=?][data-other-project-type-id=?]",
      association.id.to_s, other_type.id.to_s
    assert_select "select#project_association_other_project_id option[value=?][data-project-type-id=?]",
      caso.id.to_s, other_type.id.to_s
  end

  test "index's Responsable filter select is marked for TomSelect" do
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_type_projects_path(project_types(:instalaciones).slug)
    assert_response :success
    assert_select "select.js-tomselect[name=?]", "responsible_id"
  end

  test "index's bulk-assign Responsable select is marked for TomSelect" do
    slug = project_types(:instalaciones).slug
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_type_projects_path(slug)
    assert_response :success
    assert_select "select#bulk-assign-responsible-select-#{slug}.js-tomselect"
  end

  test "show's Asociaciones Tipo de asociación select stays a plain native select" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_path(project)
    assert_response :success
    assert_select "select#project_association_project_type_association_id.js-tomselect", count: 0
  end

  test "tracker's Responsable filter select is marked for TomSelect" do
    get tracker_projects_path
    assert_response :success
    assert_select "select.js-tomselect[name=?]", "responsible_id"
  end

  test "show's Responsables assignment select is marked for TomSelect" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_path(project)
    assert_response :success
    assert_select "select.js-tomselect#project_responsible_responsible_id"
  end

  test "show's Asociaciones Proyecto select is marked for TomSelect" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_path(project)
    assert_response :success
    assert_select "select.js-tomselect#project_association_other_project_id"
  end

  test "show marks a historical (deleted) responsible assignment" do
    project_type = project_types(:instalaciones)
    responsible_type = ResponsibleType.create!(project_type: project_type, name: "Instalador")
    responsible = Responsible.create!(name: "Ana Gómez")
    ResponsibleProjectType.create!(responsible: responsible, project_type: project_type)
    project = Project.create!(project_type: project_type, name: "Torre Norte", custom_fields: {})
    ProjectResponsible.create!(project: project, responsible: responsible, responsible_type: responsible_type)
    responsible.destroy

    get project_path(project)

    assert_response :success
    assert_select "body", /Ana Gómez \(eliminado\)/
  end

  test "show does not mark an active responsible assignment as deleted" do
    project_type = project_types(:instalaciones)
    responsible_type = ResponsibleType.create!(project_type: project_type, name: "Instalador")
    responsible = Responsible.create!(name: "Ana Gómez")
    ResponsibleProjectType.create!(responsible: responsible, project_type: project_type)
    project = Project.create!(project_type: project_type, name: "Torre Norte", custom_fields: {})
    ProjectResponsible.create!(project: project, responsible: responsible, responsible_type: responsible_type)

    get project_path(project)

    assert_response :success
    assert_select "body", /Ana Gómez/
    assert_select "body", { text: /Ana Gómez \(eliminado\)/, count: 0 }
  end
end
