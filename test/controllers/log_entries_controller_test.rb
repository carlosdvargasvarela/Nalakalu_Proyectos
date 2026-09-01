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

  test "create succeeds for a visor with view access via ProjectAccess" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    ProjectAccess.create!(user: users(:maria), project: project)

    sign_in users(:maria)
    assert_difference("project.log_entries.count", 1) do
      post project_log_entries_path(project), params: {
        log_entry: { body: "Nota de visor", log_entry_type_id: log_entry_types(:nota).id }
      }
    end
  end

  test "create succeeds for a visor with view access via their linked responsible" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    visor = User.create!(email: "visor-bitacora@example.com", password: "password123", role: "visor", confirmed_at: Time.current)
    responsible = Responsible.create!(name: "Visor Bitácora", user: visor)
    ResponsibleProjectType.create!(responsible: responsible, project_type: project_types(:instalaciones), responsible_type: responsible_types(:instalador))
    ProjectResponsible.create!(project: project, responsible: responsible, responsible_type: responsible_types(:instalador))

    sign_in visor
    assert_difference("project.log_entries.count", 1) do
      post project_log_entries_path(project), params: {
        log_entry: { body: "Nota de visor por responsable", log_entry_type_id: log_entry_types(:nota).id }
      }
    end
  end

  test "create is blocked for a visor without any view access" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})

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

  test "destroy is blocked once the author's edit access is revoked" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    access = ProjectAccess.create!(user: users(:carla), project: project, can_edit: true)
    entry = LogEntry.create!(project: project, user: users(:carla), log_entry_type: log_entry_types(:nota), body: "Nota de carla")
    access.update!(can_edit: false)

    sign_in users(:carla)
    assert_no_difference("LogEntry.count") do
      delete project_log_entry_path(project, entry)
    end
  end

  test "update changes the body and type of the author's own entry" do
    entry = LogEntry.create!(project: @project, user: users(:juan), log_entry_type: log_entry_types(:nota), body: "Nota original")
    other_type = log_entry_types(:incidencia)

    patch project_log_entry_path(@project, entry), params: {
      log_entry: { body: "Nota corregida", log_entry_type_id: other_type.id }
    }

    assert_redirected_to project_path(@project)
    entry.reload
    assert_equal "Nota corregida", entry.body.to_plain_text
    assert_equal other_type, entry.log_entry_type
  end

  test "update is blocked for a log entry owned by another user (non-admin/gerente signed in)" do
    ProjectAccess.create!(user: users(:maria), project: @project)
    entry = LogEntry.create!(project: @project, user: users(:juan), log_entry_type: log_entry_types(:nota), body: "Ajena")

    sign_in users(:maria)
    patch project_log_entry_path(@project, entry), params: {
      log_entry: { body: "Intento de edición ajena" }
    }

    assert_redirected_to project_path(@project)
    assert_equal "Ajena", entry.reload.body.to_plain_text
  end

  test "update succeeds for an admin editing another user's entry" do
    entry = LogEntry.create!(project: @project, user: users(:maria), log_entry_type: log_entry_types(:nota), body: "Nota de otro")

    # setup already signs in users(:juan), whose fixture role is admin
    patch project_log_entry_path(@project, entry), params: {
      log_entry: { body: "Corregida por admin" }
    }

    assert_equal "Corregida por admin", entry.reload.body.to_plain_text
  end

  test "update succeeds for a gerente editing another user's entry" do
    entry = LogEntry.create!(project: @project, user: users(:juan), log_entry_type: log_entry_types(:nota), body: "Nota de juan")

    sign_in users(:carla)
    patch project_log_entry_path(@project, entry), params: {
      log_entry: { body: "Corregida por gerente" }
    }

    assert_equal "Corregida por gerente", entry.reload.body.to_plain_text
  end

  test "update is blocked once the author's edit access is revoked (non-admin/gerente author)" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    access = ProjectAccess.create!(user: users(:pedro), project: project, can_edit: true)
    entry = LogEntry.create!(project: project, user: users(:pedro), log_entry_type: log_entry_types(:nota), body: "Nota de pedro")
    access.update!(can_edit: false)

    sign_in users(:pedro)
    patch project_log_entry_path(project, entry), params: { log_entry: { body: "Intento tras revocación" } }

    assert_equal "Nota de pedro", entry.reload.body.to_plain_text
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
