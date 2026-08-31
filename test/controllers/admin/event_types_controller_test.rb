require "test_helper"

class Admin::EventTypesControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:juan) }
  setup { @project_type = project_types(:instalaciones) }

  test "create adds an event type to the project type" do
    assert_difference("@project_type.event_types.count", 1) do
      post admin_project_type_event_types_path(@project_type), params: {
        event_type: { name: "Visita técnica", position: 3, color: "#123abc", icon: "bi-tools" }
      }
    end
    assert_redirected_to admin_project_type_path(@project_type)
  end

  test "create with blank name re-renders form with error" do
    assert_no_difference("@project_type.event_types.count") do
      post admin_project_type_event_types_path(@project_type), params: {
        event_type: { name: "", position: 3 }
      }
    end
    assert_response :unprocessable_entity
  end

  test "update saves the color and icon" do
    event_type = event_types(:reunion_obra)
    patch admin_project_type_event_type_path(@project_type, event_type), params: {
      event_type: { name: event_type.name, position: event_type.position, color: "#f60404", icon: "bi-flag" }
    }
    assert_redirected_to admin_project_type_path(@project_type)
    assert_equal "#f60404", event_type.reload.color
    assert_equal "bi-flag", event_type.reload.icon
  end

  test "destroy removes an event type with no events" do
    event_type = event_types(:reunion_obra)
    assert_difference("@project_type.event_types.count", -1) do
      delete admin_project_type_event_type_path(@project_type, event_type)
    end
  end

  test "destroy with existing events redirects with an error instead of destroying" do
    project = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: {})
    event_type = event_types(:reunion_obra)
    Event.create!(project: project, event_type: event_type, title: "Kickoff", event_date: Date.current)

    assert_no_difference("@project_type.event_types.count") do
      delete admin_project_type_event_type_path(@project_type, event_type)
    end
    assert_redirected_to admin_project_type_path(@project_type)
  end

  test "reorder updates position according to the submitted id order" do
    reunion = event_types(:reunion_obra)
    entrega = event_types(:entrega_final)

    patch reorder_admin_project_type_event_types_path(@project_type), params: { ids: [entrega.id, reunion.id] }, as: :json
    assert_response :success

    assert_equal 0, entrega.reload.position
    assert_equal 1, reunion.reload.position
  end

  test "new and edit show the submit button in Spanish" do
    get new_admin_project_type_event_type_path(@project_type)
    assert_response :success
    assert_select "input[value=?]", "Crear Tipo De Evento"

    get edit_admin_project_type_event_type_path(@project_type, event_types(:reunion_obra))
    assert_response :success
    assert_select "input[value=?]", "Actualizar Tipo De Evento"
  end
end
