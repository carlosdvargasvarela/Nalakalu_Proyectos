require "test_helper"

class LogEntriesControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:juan) }
  setup { @project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {}) }

  test "create adds a log_entry authored by the signed-in user" do
    assert_difference("@project.log_entries.count", 1) do
      post project_log_entries_path(@project), params: {
        log_entry: { body: "Instalación completada", log_entry_type_id: log_entry_types(:nota).id }
      }
    end
    assert_equal users(:juan), @project.log_entries.last.user
    assert_redirected_to project_path(@project)
  end

  test "create with blank body does not create a log_entry" do
    assert_no_difference("@project.log_entries.count") do
      post project_log_entries_path(@project), params: {
        log_entry: { body: "", log_entry_type_id: log_entry_types(:nota).id }
      }
    end
  end

  test "destroy removes a log_entry owned by the signed-in user" do
    entry = LogEntry.create!(project: @project, user: users(:juan), log_entry_type: log_entry_types(:nota), body: "Nota propia")
    assert_difference("LogEntry.count", -1) do
      delete project_log_entry_path(@project, entry)
    end
  end

  test "destroy does not remove a log_entry owned by another user" do
    other_user = User.create!(email: "otro@example.com", password: "password123")
    entry = LogEntry.create!(project: @project, user: other_user, log_entry_type: log_entry_types(:nota), body: "Ajena")

    assert_no_difference("LogEntry.count") do
      delete project_log_entry_path(@project, entry)
    end
  end

  test "create is blocked for a visor even with view access" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    ProjectAccess.create!(user: users(:maria), project: project)

    sign_in users(:maria)
    assert_no_difference("project.log_entries.count") do
      post project_log_entries_path(project), params: {
        log_entry: { body: "Intento de nota", log_entry_type_id: log_entry_types(:nota).id }
      }
    end
  end

  test "create is blocked for a gerente without edit access" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})

    sign_in users(:carla)
    assert_no_difference("project.log_entries.count") do
      post project_log_entries_path(project), params: {
        log_entry: { body: "Intento de nota", log_entry_type_id: log_entry_types(:nota).id }
      }
    end
  end

  test "create succeeds for a gerente with edit access" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    ProjectAccess.create!(user: users(:carla), project: project, can_edit: true)

    sign_in users(:carla)
    assert_difference("project.log_entries.count", 1) do
      post project_log_entries_path(project), params: {
        log_entry: { body: "Nota autorizada", log_entry_type_id: log_entry_types(:nota).id }
      }
    end
  end
end
