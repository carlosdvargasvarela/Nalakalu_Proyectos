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

  test "show wires the drag-reorder script to the correct endpoints" do
    project_type = project_types(:instalaciones)
    get admin_project_type_path(project_type)
    assert_response :success
    assert_match(/initDragReorder\("field-definitions-list",\s*"#{Regexp.escape(reorder_admin_project_type_field_definitions_path(project_type))}"\)/, response.body)
    assert_match(/initDragReorder\("stage-templates-list",\s*"#{Regexp.escape(reorder_admin_project_type_stage_templates_path(project_type))}"\)/, response.body)
  end
end
