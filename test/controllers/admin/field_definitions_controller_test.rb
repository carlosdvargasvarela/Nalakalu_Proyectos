require "test_helper"

class Admin::FieldDefinitionsControllerTest < ActionDispatch::IntegrationTest
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
end
