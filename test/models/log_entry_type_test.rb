require "test_helper"

class LogEntryTypeTest < ActiveSupport::TestCase
  test "valid with name, color and project_type" do
    type = LogEntryType.new(project_type: project_types(:instalaciones), name: "Nota", color: "#6c757d")
    assert type.valid?
  end

  test "invalid without name" do
    type = LogEntryType.new(project_type: project_types(:instalaciones), color: "#6c757d")
    assert_not type.valid?
  end

  test "invalid with a malformed color" do
    type = LogEntryType.new(project_type: project_types(:instalaciones), name: "Nota", color: "blue")
    assert_not type.valid?
  end

  test "valid with default color" do
    type = LogEntryType.new(project_type: project_types(:instalaciones), name: "Nota")
    assert type.valid?
    assert_equal "#6c757d", type.color
  end
end
