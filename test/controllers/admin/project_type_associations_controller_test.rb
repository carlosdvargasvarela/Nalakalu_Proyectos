require "test_helper"

class Admin::ProjectTypeAssociationsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:juan) }
  setup { @other_type = ProjectType.create!(name: "Caso de Servicio", slug: "caso-de-servicio") }

  test "index lists project type associations" do
    ProjectTypeAssociation.create!(from_project_type: @other_type, to_project_type: project_types(:instalaciones), label: "Caso de servicio")
    get admin_project_type_associations_path
    assert_response :success
    assert_select "body", /Caso de servicio/
  end

  test "create adds a new project type association" do
    assert_difference("ProjectTypeAssociation.count", 1) do
      post admin_project_type_associations_path, params: {
        project_type_association: {
          from_project_type_id: @other_type.id, to_project_type_id: project_types(:instalaciones).id,
          label: "Caso de servicio", responsables_can_create: "1"
        }
      }
    end
    assert_redirected_to admin_project_type_associations_path
    assert ProjectTypeAssociation.order(:id).last.responsables_can_create
  end

  test "create with blank label re-renders form with error" do
    assert_no_difference("ProjectTypeAssociation.count") do
      post admin_project_type_associations_path, params: {
        project_type_association: { from_project_type_id: @other_type.id, to_project_type_id: project_types(:instalaciones).id, label: "" }
      }
    end
    assert_response :unprocessable_entity
  end

  test "update changes the label and the responsables_can_create flag" do
    pta = ProjectTypeAssociation.create!(from_project_type: @other_type, to_project_type: project_types(:instalaciones), label: "Caso de servicio")
    patch admin_project_type_association_path(pta), params: {
      project_type_association: {
        from_project_type_id: @other_type.id, to_project_type_id: project_types(:instalaciones).id,
        label: "Caso de Servicio Actualizado", responsables_can_create: "1"
      }
    }
    assert_redirected_to admin_project_type_associations_path
    pta.reload
    assert_equal "Caso de Servicio Actualizado", pta.label
    assert pta.responsables_can_create
  end

  test "destroy removes a project type association" do
    pta = ProjectTypeAssociation.create!(from_project_type: @other_type, to_project_type: project_types(:instalaciones), label: "Caso de servicio")
    assert_difference("ProjectTypeAssociation.count", -1) do
      delete admin_project_type_association_path(pta)
    end
  end

  test "create persists shared_field_mappings" do
    assert_difference("ProjectTypeAssociation.count", 1) do
      post admin_project_type_associations_path, params: {
        project_type_association: {
          from_project_type_id: @other_type.id, to_project_type_id: project_types(:instalaciones).id,
          label: "Caso de servicio", shared_field_mappings: [{ from: "cliente", to: "nombre_cliente" }]
        }
      }
    end
    assert_equal [{ "from" => "cliente", "to" => "nombre_cliente" }], ProjectTypeAssociation.order(:id).last.shared_field_mappings
  end

  test "update with no mapping rows left clears the list" do
    pta = ProjectTypeAssociation.create!(
      from_project_type: @other_type, to_project_type: project_types(:instalaciones),
      label: "Caso de servicio", shared_field_mappings: [{ from: "cliente", to: "nombre_cliente" }]
    )
    patch admin_project_type_association_path(pta), params: {
      project_type_association: {
        from_project_type_id: @other_type.id, to_project_type_id: project_types(:instalaciones).id,
        label: "Caso de servicio", shared_field_mappings: []
      }
    }
    assert_equal [], pta.reload.shared_field_mappings
  end

  test "create drops incomplete mapping rows (missing from or to)" do
    post admin_project_type_associations_path, params: {
      project_type_association: {
        from_project_type_id: @other_type.id, to_project_type_id: project_types(:instalaciones).id,
        label: "Caso de servicio",
        shared_field_mappings: [{ from: "cliente", to: "" }, { from: "", to: "nombre_cliente" }, { from: "cliente", to: "nombre_cliente" }]
      }
    }
    assert_equal [{ "from" => "cliente", "to" => "nombre_cliente" }], ProjectTypeAssociation.order(:id).last.shared_field_mappings
  end

  test "new exposes field definitions grouped by project type" do
    get new_admin_project_type_association_path
    assert_response :success
    assert_select "script#field-definitions-by-type", 1
  end
end
