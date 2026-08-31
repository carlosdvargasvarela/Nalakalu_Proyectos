require "test_helper"

class EventsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:juan) }
  setup do
    @project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    @event_type = event_types(:reunion_obra)
  end

  test "create adds a project-wide event" do
    assert_difference("@project.events.count", 1) do
      post project_events_path(@project), params: {
        event: { event_type_id: @event_type.id, title: "Kickoff", event_date: Date.current }
      }
    end
    assert_redirected_to project_path(@project)
    assert @project.events.last.project_wide?
  end

  test "create adds a stage-scoped event" do
    stage = @project.project_stages.first
    post project_events_path(@project), params: {
      event: { event_type_id: @event_type.id, title: "Kickoff", event_date: Date.current, project_stage_id: stage.id }
    }
    assert_equal stage, @project.events.last.project_stage
  end

  test "create with a blank title redirects with an error" do
    assert_no_difference("@project.events.count") do
      post project_events_path(@project), params: {
        event: { event_type_id: @event_type.id, title: "", event_date: Date.current }
      }
    end
    assert_redirected_to project_path(@project)
  end

  test "update changes an event's fields" do
    event = Event.create!(project: @project, event_type: @event_type, title: "Kickoff", event_date: Date.current)
    patch project_event_path(@project, event), params: { event: { title: "Kickoff reprogramado", status: "realizado" } }
    assert_redirected_to project_path(@project)
    event.reload
    assert_equal "Kickoff reprogramado", event.title
    assert_equal "realizado", event.status
  end

  test "destroy removes an event" do
    event = Event.create!(project: @project, event_type: @event_type, title: "Kickoff", event_date: Date.current)
    assert_difference("@project.events.count", -1) do
      delete project_event_path(@project, event)
    end
  end

  test "visor without edit access cannot create an event" do
    sign_in users(:maria)
    assert_no_difference("@project.events.count") do
      post project_events_path(@project), params: {
        event: { event_type_id: @event_type.id, title: "Kickoff", event_date: Date.current }
      }
    end
    assert_redirected_to root_path
  end
end
