require "test_helper"

class ProjectAssociationsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:juan) }
  setup do
    @caso_type = ProjectType.create!(name: "Caso de Servicio", slug: "caso-de-servicio")
    @association = ProjectTypeAssociation.create!(from_project_type: @caso_type, to_project_type: project_types(:instalaciones), label: "Caso de servicio")
    @instalacion = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    @caso = Project.create!(project_type: @caso_type, name: "Ticket 1", custom_fields: {})
  end

  test "create links an existing caso to an instalacion when starting from the instalacion" do
    assert_difference("ProjectAssociation.count", 1) do
      post project_project_associations_path(@instalacion), params: {
        project_association: { project_type_association_id: @association.id, other_project_id: @caso.id }
      }
    end
    assert_redirected_to project_path(@instalacion)
    pa = ProjectAssociation.order(:id).last
    assert_equal @caso, pa.from_project
    assert_equal @instalacion, pa.to_project
  end

  test "create links starting from the caso, resolving direction automatically" do
    assert_difference("ProjectAssociation.count", 1) do
      post project_project_associations_path(@caso), params: {
        project_association: { project_type_association_id: @association.id, other_project_id: @instalacion.id }
      }
    end
    pa = ProjectAssociation.order(:id).last
    assert_equal @caso, pa.from_project
    assert_equal @instalacion, pa.to_project
  end

  test "create with a mismatched project renders an error and creates nothing" do
    other_instalacion = Project.create!(project_type: project_types(:instalaciones), name: "Otra", custom_fields: {})
    assert_no_difference("ProjectAssociation.count") do
      post project_project_associations_path(@instalacion), params: {
        project_association: { project_type_association_id: @association.id, other_project_id: other_instalacion.id }
      }
    end
    assert_redirected_to project_path(@instalacion)
  end

  test "destroy removes an association" do
    pa = ProjectAssociation.create!(from_project: @caso, to_project: @instalacion, project_type_association: @association)
    assert_difference("ProjectAssociation.count", -1) do
      delete project_project_association_path(@instalacion, pa)
    end
  end

  test "visor without edit access cannot create an association" do
    sign_in users(:maria)
    assert_no_difference("ProjectAssociation.count") do
      post project_project_associations_path(@instalacion), params: {
        project_association: { project_type_association_id: @association.id, other_project_id: @caso.id }
      }
    end
    assert_redirected_to root_path
  end
end
