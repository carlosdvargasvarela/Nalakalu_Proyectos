require "test_helper"

class ProjectAssociationTest < ActiveSupport::TestCase
  setup do
    @caso_type = ProjectType.create!(name: "Caso de Servicio", slug: "caso-de-servicio")
    @association = ProjectTypeAssociation.create!(from_project_type: @caso_type, to_project_type: project_types(:instalaciones), label: "Caso de servicio")
    @instalacion = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    @caso = Project.create!(project_type: @caso_type, name: "Ticket 1", custom_fields: {})
  end

  test "valid when both projects match the association's expected types" do
    pa = ProjectAssociation.new(from_project: @caso, to_project: @instalacion, project_type_association: @association)
    assert pa.valid?
  end

  test "invalid when from_project's type doesn't match" do
    other_caso = Project.create!(project_type: project_types(:instalaciones), name: "Otro", custom_fields: {})
    pa = ProjectAssociation.new(from_project: other_caso, to_project: @instalacion, project_type_association: @association)
    assert_not pa.valid?
  end

  test "invalid when to_project's type doesn't match" do
    other_instalacion = Project.create!(project_type: @caso_type, name: "Otro", custom_fields: {})
    pa = ProjectAssociation.new(from_project: @caso, to_project: other_instalacion, project_type_association: @association)
    assert_not pa.valid?
  end

  test "invalid associating a project with itself" do
    pa = ProjectAssociation.new(from_project: @instalacion, to_project: @instalacion, project_type_association:
      ProjectTypeAssociation.create!(from_project_type: project_types(:instalaciones), to_project_type: project_types(:instalaciones), label: "Relacionado"))
    assert_not pa.valid?
  end

  test "project exposes its outgoing and incoming associations" do
    pa = ProjectAssociation.create!(from_project: @caso, to_project: @instalacion, project_type_association: @association)
    assert_equal [pa], @caso.outgoing_project_associations.to_a
    assert_equal [pa], @instalacion.incoming_project_associations.to_a
  end
end
