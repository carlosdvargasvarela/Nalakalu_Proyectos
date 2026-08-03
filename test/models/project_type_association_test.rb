require "test_helper"

class ProjectTypeAssociationTest < ActiveSupport::TestCase
  test "valid with from/to project types and a label" do
    other_type = ProjectType.create!(name: "Caso de Servicio", slug: "caso-de-servicio")
    pta = ProjectTypeAssociation.new(from_project_type: other_type, to_project_type: project_types(:instalaciones), label: "Caso de servicio")
    assert pta.valid?
  end

  test "invalid without a label" do
    other_type = ProjectType.create!(name: "Caso de Servicio", slug: "caso-de-servicio")
    pta = ProjectTypeAssociation.new(from_project_type: other_type, to_project_type: project_types(:instalaciones))
    assert_not pta.valid?
  end

  test "responsables_can_create defaults to false" do
    other_type = ProjectType.create!(name: "Caso de Servicio", slug: "caso-de-servicio")
    pta = ProjectTypeAssociation.create!(from_project_type: other_type, to_project_type: project_types(:instalaciones), label: "Caso de servicio")
    assert_equal false, pta.responsables_can_create
  end

  test "shared_field_mappings defaults to an empty array" do
    other_type = ProjectType.create!(name: "Caso de Servicio", slug: "caso-de-servicio")
    pta = ProjectTypeAssociation.create!(from_project_type: other_type, to_project_type: project_types(:instalaciones), label: "Caso de servicio")
    assert_equal [], pta.shared_field_mappings
  end

  test "shared_field_mappings persists an array of from/to pairs" do
    other_type = ProjectType.create!(name: "Caso de Servicio", slug: "caso-de-servicio")
    pta = ProjectTypeAssociation.create!(
      from_project_type: other_type, to_project_type: project_types(:instalaciones),
      label: "Caso de servicio", shared_field_mappings: [{ from: "cliente", to: "nombre_cliente" }]
    )
    assert_equal [{ "from" => "cliente", "to" => "nombre_cliente" }], pta.reload.shared_field_mappings
  end
end
