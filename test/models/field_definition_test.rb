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

  test "invalid reference field without a reference_table" do
    field = FieldDefinition.new(
      project_type: project_types(:instalaciones),
      key: "supervisor", label: "Supervisor", data_type: "reference"
    )
    assert_not field.valid?
  end

  test "data_type_label translates every known type to Spanish" do
    expected = {
      "text" => "Texto", "textarea" => "Texto largo", "number" => "Número",
      "currency" => "Monto (₡)", "percent" => "Porcentaje", "date" => "Fecha",
      "boolean" => "Sí/No", "reference" => "Referencia"
    }
    expected.each do |data_type, label|
      field = FieldDefinition.new(project_type: project_types(:instalaciones), key: "x", label: "X", data_type: data_type)
      assert_equal label, field.data_type_label
    end
  end

  test "data_type_label falls back to the raw value for an unknown type" do
    field = FieldDefinition.new(project_type: project_types(:instalaciones), key: "x", label: "X", data_type: "text")
    field.data_type = "weird_type"
    assert_equal "weird_type", field.data_type_label
  end

  test "valid with each of the new data types" do
    %w[number currency textarea boolean].each do |data_type|
      field = FieldDefinition.new(
        project_type: project_types(:instalaciones), key: "campo_#{data_type}", label: "Campo", data_type: data_type
      )
      assert field.valid?, "#{data_type}: #{field.errors.full_messages}"
    end
  end
end
