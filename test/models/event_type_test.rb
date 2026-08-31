require "test_helper"

class EventTypeTest < ActiveSupport::TestCase
  test "valid with name" do
    event_type = EventType.new(project_type: project_types(:instalaciones), name: "Reunión")
    assert event_type.valid?
  end

  test "invalid without name" do
    event_type = EventType.new(project_type: project_types(:instalaciones))
    assert_not event_type.valid?
  end

  test "valid with default color and icon" do
    event_type = EventType.new(project_type: project_types(:instalaciones), name: "Reunión")
    assert event_type.valid?
    assert_equal "#6c757d", event_type.color
    assert_equal "bi-calendar-event", event_type.icon
  end

  test "invalid with a malformed color" do
    event_type = EventType.new(project_type: project_types(:instalaciones), name: "Reunión", color: "blue")
    assert_not event_type.valid?
  end

  test "project_type has_many event_types ordered by position" do
    ordered = project_types(:instalaciones).event_types.map(&:name)
    assert_equal ["Reunión de obra", "Entrega final"], ordered
  end
end
