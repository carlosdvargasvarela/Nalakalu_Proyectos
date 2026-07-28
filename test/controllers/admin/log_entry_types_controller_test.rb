require "test_helper"

class Admin::LogEntryTypesControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:juan) }
  setup { @project_type = project_types(:instalaciones) }

  test "create adds a log_entry_type to the project type" do
    assert_difference("@project_type.log_entry_types.count", 1) do
      post admin_project_type_log_entry_types_path(@project_type), params: {
        log_entry_type: { name: "Advertencia", color: "#ffc107" }
      }
    end
    assert_redirected_to admin_project_type_path(@project_type)
  end

  test "create with blank name re-renders form with error" do
    assert_no_difference("@project_type.log_entry_types.count") do
      post admin_project_type_log_entry_types_path(@project_type), params: {
        log_entry_type: { name: "", color: "#ffc107" }
      }
    end
    assert_response :unprocessable_entity
  end

  test "update saves the name and color" do
    type = log_entry_types(:nota)
    patch admin_project_type_log_entry_type_path(@project_type, type), params: {
      log_entry_type: { name: "Nota importante", color: "#f60404" }
    }
    assert_redirected_to admin_project_type_path(@project_type)
    type.reload
    assert_equal "Nota importante", type.name
    assert_equal "#f60404", type.color
  end

  test "destroy removes a log_entry_type" do
    type = log_entry_types(:cambio)
    assert_difference("@project_type.log_entry_types.count", -1) do
      delete admin_project_type_log_entry_type_path(@project_type, type)
    end
  end

  test "destroy with associated log_entries does not delete the type and sets a flash alert" do
    type = log_entry_types(:cambio)
    project = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: {})
    LogEntry.create!(project: project, user: users(:juan), log_entry_type: type, body: "Nota")

    assert_no_difference("@project_type.log_entry_types.count") do
      delete admin_project_type_log_entry_type_path(@project_type, type)
    end
    assert_redirected_to admin_project_type_path(@project_type)
    assert_not_nil flash[:alert]
  end
end
