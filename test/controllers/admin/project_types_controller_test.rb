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

  test "show renders Eliminar as a real delete form for each field definition" do
    project_type = project_types(:instalaciones)
    field = field_definitions(:cliente)
    get admin_project_type_path(project_type)
    assert_response :success
    assert_select "form[action=?]", admin_project_type_field_definition_path(project_type, field) do
      assert_select "input[name=?][value=?]", "_method", "delete"
      assert_select "button", "Eliminar"
    end
  end

  test "show renders Eliminar as a real delete form for each stage template" do
    project_type = project_types(:instalaciones)
    stage = stage_templates(:entrega)
    get admin_project_type_path(project_type)
    assert_response :success
    assert_select "form[action=?]", admin_project_type_stage_template_path(project_type, stage) do
      assert_select "input[name=?][value=?]", "_method", "delete"
      assert_select "button", "Eliminar"
    end
  end

  test "show asks for confirmation before deleting a field definition or stage template" do
    project_type = project_types(:instalaciones)
    field = field_definitions(:cliente)
    stage = stage_templates(:entrega)
    get admin_project_type_path(project_type)
    assert_response :success
    assert_select "form[action=?][onsubmit=?]",
      admin_project_type_field_definition_path(project_type, field), "return confirm('¿Eliminar campo?')"
    assert_select "form[action=?][onsubmit=?]",
      admin_project_type_stage_template_path(project_type, stage), "return confirm('¿Eliminar subproceso?')"
  end

  test "show groups Campos and Subprocesos into cards" do
    get admin_project_type_path(project_types(:instalaciones))
    assert_response :success
    assert_select ".card .card-header", "Campos"
    assert_select ".card .card-header", "Subprocesos"
  end

  test "new and edit show the submit button in Spanish" do
    get new_admin_project_type_path
    assert_response :success
    assert_select "input[value=?]", "Crear Tipo de proyecto"

    get edit_admin_project_type_path(project_types(:instalaciones))
    assert_response :success
    assert_select "input[value=?]", "Actualizar Tipo de proyecto"
  end

  test "show displays the Spanish label for a field's data type, not the raw value" do
    get admin_project_type_path(project_types(:instalaciones))
    assert_response :success
    assert_select "body", /Texto/
    assert_no_match(/\(text\)/, response.body)
  end

  test "show renders a drag handle and data-id for each field definition and stage template" do
    project_type = project_types(:instalaciones)
    field = field_definitions(:cliente)
    stage = stage_templates(:entrega)

    get admin_project_type_path(project_type)
    assert_response :success
    assert_select "#field-definitions-list li[data-id=?] .drag-handle", field.id.to_s
    assert_select "#stage-templates-list li[data-id=?] .drag-handle", stage.id.to_s
  end

  test "show wires the drag-reorder controller to the correct endpoints" do
    project_type = project_types(:instalaciones)
    get admin_project_type_path(project_type)
    assert_response :success
    assert_select "#field-definitions-list[data-controller=?][data-drag-reorder-url-value=?]",
      "drag-reorder", reorder_admin_project_type_field_definitions_path(project_type)
    assert_select "#stage-templates-list[data-controller=?][data-drag-reorder-url-value=?]",
      "drag-reorder", reorder_admin_project_type_stage_templates_path(project_type)
  end

  test "show lists only the Responsible catalog entries enabled for this project type" do
    enabled = Responsible.create!(name: "Ana Gómez", color: "#ff0000")
    ResponsibleProjectType.create!(responsible: enabled, project_type: project_types(:instalaciones), responsible_type: responsible_types(:instalador))
    other_type = ProjectType.create!(name: "Mantenimiento", slug: "mantenimiento")
    other_responsible_type = ResponsibleType.create!(project_type: other_type, name: "Supervisor")
    not_enabled = Responsible.create!(name: "No Habilitado")
    ResponsibleProjectType.create!(responsible: not_enabled, project_type: other_type, responsible_type: other_responsible_type)

    get admin_project_type_path(project_types(:instalaciones))
    assert_response :success
    assert_select ".card-header", "Responsables"
    assert_select "body", /Ana Gómez/
    assert_no_match(/No Habilitado/, response.body)
    assert_select "a[href=?]", admin_responsibles_path, text: "Administrar responsables"
  end

  test "new form includes the require_stage_dates checkbox" do
    get new_admin_project_type_path
    assert_response :success
    assert_select "input[type=checkbox][name=?]", "project_type[require_stage_dates]"
  end

  test "create persists require_stage_dates when checked" do
    post admin_project_types_path, params: { project_type: { name: "Mantenimiento", slug: "mantenimiento", require_stage_dates: "1" } }
    assert_equal true, ProjectType.last.require_stage_dates
  end

  test "show displays the Cálculo automático de duración card" do
    get admin_project_type_path(project_types(:instalaciones))
    assert_response :success
    assert_select ".card-header", "Cálculo automático de duración"
  end

  test "show's auto-duration form only lists numeric field definitions as reference options" do
    project_type = project_types(:instalaciones)
    FieldDefinition.create!(project_type: project_type, key: "cantidad", label: "Cantidad de Unidades", data_type: "number", position: 10)
    FieldDefinition.create!(project_type: project_type, key: "notas", label: "Notas", data_type: "textarea", position: 11)

    get admin_project_type_path(project_type)
    assert_response :success
    assert_select "select[name=?] option", "project_type[duration_reference_field_definition_id]", text: "Cantidad de Unidades"
    assert_select "select[name=?] option", "project_type[duration_reference_field_definition_id]", text: "Notas", count: 0
  end

  test "update persists auto_stage_duration_enabled and duration_reference_field_definition_id" do
    project_type = project_types(:instalaciones)
    field = FieldDefinition.create!(project_type: project_type, key: "cantidad", label: "Cantidad", data_type: "number", position: 10)

    patch admin_project_type_path(project_type), params: {
      project_type: { name: project_type.name, slug: project_type.slug, auto_stage_duration_enabled: "1", duration_reference_field_definition_id: field.id }
    }

    assert_redirected_to admin_project_type_path(project_type)
    project_type.reload
    assert_equal true, project_type.auto_stage_duration_enabled
    assert_equal field.id, project_type.duration_reference_field_definition_id
  end
end
