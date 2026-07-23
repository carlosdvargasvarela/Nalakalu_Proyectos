require "test_helper"

class ProjectStagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:juan)
    @project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    @stage = @project.project_stages.first
  end

  test "update saves start_date, end_date, progress_percent and user" do
    patch project_project_stage_path(@project, @stage), params: {
      project_stage: {
        start_date: "2026-08-01", end_date: "2026-08-10",
        progress_percent: 50, user_id: users(:juan).id
      }
    }
    assert_redirected_to project_path(@project)

    @stage.reload
    assert_equal Date.parse("2026-08-01"), @stage.start_date
    assert_equal Date.parse("2026-08-10"), @stage.end_date
    assert_equal 50, @stage.progress_percent
    assert_equal users(:juan), @stage.user
  end

  test "update with progress_percent out of range re-renders form with error" do
    patch project_project_stage_path(@project, @stage), params: {
      project_stage: { progress_percent: 150 }
    }
    assert_response :unprocessable_entity
  end

  test "editing a stage from another project 404s" do
    other_project = Project.create!(project_type: project_types(:instalaciones), name: "Otro", custom_fields: {})
    other_stage = other_project.project_stages.first

    get edit_project_project_stage_path(@project, other_stage)
    assert_response :not_found
  end
end
