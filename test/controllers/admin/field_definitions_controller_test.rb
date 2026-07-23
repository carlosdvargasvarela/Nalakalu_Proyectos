require "test_helper"

class Admin::FieldDefinitionsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:juan) }
  setup { @project_type = project_types(:instalaciones) }

  test "create adds a field definition to the project type" do
    assert_difference("@project_type.field_definitions.count", 1) do
      post admin_project_type_field_definitions_path(@project_type), params: {
        field_definition: { key: "vendedor", label: "Vendedor", data_type: "text", position: 3, show_in_gantt: false }
      }
    end
    assert_redirected_to admin_project_type_path(@project_type)
  end

  test "create with invalid data_type re-renders form with error" do
    assert_no_difference("@project_type.field_definitions.count") do
      post admin_project_type_field_definitions_path(@project_type), params: {
        field_definition: { key: "vendedor", label: "Vendedor", data_type: "bogus" }
      }
    end
    assert_response :unprocessable_entity
  end

  test "destroy removes a field definition" do
    field = field_definitions(:cliente)
    assert_difference("@project_type.field_definitions.count", -1) do
      delete admin_project_type_field_definition_path(@project_type, field)
    end
  end

  test "new and edit show the submit button in Spanish" do
    get new_admin_project_type_field_definition_path(@project_type)
    assert_response :success
    assert_select "input[value=?]", "Crear Campo"

    get edit_admin_project_type_field_definition_path(@project_type, field_definitions(:cliente))
    assert_response :success
    assert_select "input[value=?]", "Actualizar Campo"
  end

  test "reorder updates position according to the submitted id order" do
    cliente = field_definitions(:cliente)
    instalador = field_definitions(:instalador)

    patch reorder_admin_project_type_field_definitions_path(@project_type), params: { ids: [instalador.id, cliente.id] }, as: :json
    assert_response :success

    assert_equal 0, instalador.reload.position
    assert_equal 1, cliente.reload.position
    assert_equal [instalador, cliente], @project_type.field_definitions.order(:position).to_a
  end

  test "reorder ignores an id that doesn't belong to this project_type" do
    other_type = ProjectType.create!(name: "Mantenimiento", slug: "mantenimiento")
    other_field = other_type.field_definitions.create!(key: "x", label: "X", data_type: "text", position: 0)
    cliente = field_definitions(:cliente)

    patch reorder_admin_project_type_field_definitions_path(@project_type), params: { ids: [other_field.id, cliente.id] }, as: :json
    assert_response :success

    assert_equal 0, other_field.reload.position
    assert_equal 1, cliente.reload.position
  end
end
