require "test_helper"

class LogEntryTest < ActiveSupport::TestCase
  setup { @project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {}) }

  test "valid with project, user, log_entry_type and body" do
    entry = LogEntry.new(
      project: @project,
      user: users(:juan),
      log_entry_type: log_entry_types(:nota),
      body: "Se entregaron los planos."
    )
    assert entry.valid?
  end

  test "invalid without body" do
    entry = LogEntry.new(
      project: @project,
      user: users(:juan),
      log_entry_type: log_entry_types(:nota)
    )
    assert_not entry.valid?
  end

  test "body persists rich text formatting" do
    entry = LogEntry.create!(
      project: @project,
      user: users(:juan),
      log_entry_type: log_entry_types(:nota),
      body: "<strong>Urgente</strong>: revisar instalación"
    )

    entry.reload
    assert_includes entry.body.to_s, "<strong>Urgente</strong>"
  end
end
