require "test_helper"

class EventTest < ActiveSupport::TestCase
  setup do
    @project_type = project_types(:instalaciones)
    @event_type = event_types(:reunion_obra)
    @project = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: {})
  end

  test "valid with project, event_type, title and event_date" do
    event = Event.new(project: @project, event_type: @event_type, title: "Kickoff", event_date: Date.current)
    assert event.valid?
  end

  test "invalid without title" do
    event = Event.new(project: @project, event_type: @event_type, event_date: Date.current)
    assert_not event.valid?
  end

  test "invalid without event_date" do
    event = Event.new(project: @project, event_type: @event_type, title: "Kickoff")
    assert_not event.valid?
  end

  test "project_wide? is true with no project_stage" do
    event = Event.new(project: @project, event_type: @event_type, title: "Kickoff", event_date: Date.current)
    assert event.project_wide?
  end

  test "project_wide? is false when scoped to a stage" do
    stage = @project.project_stages.first
    event = Event.new(project: @project, event_type: @event_type, title: "Kickoff", event_date: Date.current, project_stage: stage)
    assert_not event.project_wide?
  end

  test "invalid when project_stage belongs to a different project" do
    other_project = Project.create!(project_type: @project_type, name: "Torre Sur", custom_fields: {})
    event = Event.new(
      project: @project, event_type: @event_type, title: "Kickoff", event_date: Date.current,
      project_stage: other_project.project_stages.first
    )
    assert_not event.valid?
  end

  test "invalid when event_type belongs to a different project_type" do
    other_type = ProjectType.create!(name: "Mantenimiento", slug: "mantenimiento")
    other_event_type = EventType.create!(project_type: other_type, name: "Visita")
    event = Event.new(project: @project, event_type: other_event_type, title: "Kickoff", event_date: Date.current)
    assert_not event.valid?
  end

  test "defaults status to pendiente" do
    event = Event.create!(project: @project, event_type: @event_type, title: "Kickoff", event_date: Date.current)
    assert_equal "pendiente", event.status
  end

  test "invalid when the responsible is not enabled for the project's type" do
    outsider = Responsible.create!(name: "Outsider")
    event = Event.new(project: @project, event_type: @event_type, title: "Kickoff", event_date: Date.current, responsible: outsider)
    assert_not event.valid?
    assert_includes event.errors[:responsible].join, "habilitado"
  end

  test "valid when the responsible is enabled for the project's type" do
    responsible = Responsible.create!(name: "Ana Gómez")
    responsible_type = ResponsibleType.create!(project_type: @project_type, name: "Instalador")
    ResponsibleProjectType.create!(responsible: responsible, project_type: @project_type, responsible_type: responsible_type)
    event = Event.new(project: @project, event_type: @event_type, title: "Kickoff", event_date: Date.current, responsible: responsible)
    assert event.valid?
  end

  test "deleting a project_stage nullifies its events instead of destroying them" do
    stage = @project.project_stages.first
    event = Event.create!(project: @project, event_type: @event_type, title: "Kickoff", event_date: Date.current, project_stage: stage)
    stage.destroy
    assert event.reload.project_stage_id.nil?
  end
end
