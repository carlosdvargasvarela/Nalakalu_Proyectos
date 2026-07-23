require "test_helper"

class FieldDefinitionTest < ActiveSupport::TestCase
  test "valid with required attributes" do
    field = FieldDefinition.new(
      project_type: project_types(:instalaciones),
      key: "vendedor", label: "Vendedor", data_type: "text"
    )
    assert field.valid?
  end

  test "invalid with unknown data_type" do
    field = FieldDefinition.new(
      project_type: project_types(:instalaciones),
      key: "vendedor", label: "Vendedor", data_type: "bogus"
    )
    assert_not field.valid?
  end

  test "invalid with duplicate key for same project_type" do
    dup = FieldDefinition.new(
      project_type: project_types(:instalaciones),
      key: "cliente", label: "Cliente 2", data_type: "text"
    )
    assert_not dup.valid?
  end
end
