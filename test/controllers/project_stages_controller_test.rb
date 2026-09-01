require "test_helper"

class ProjectStagesControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:juan) }
  setup do
    @project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
  end

  test "create adds a project-specific stage with no stage_template" do
    assert_difference("@project.project_stages.count", 1) do
      post project_project_stages_path(@project), params: {
        project_stage: { name: "Etapa propia", start_date: "2026-01-01", end_date: "2026-01-10" }
      }
    end
    assert_redirected_to project_path(@project)
    stage = @project.project_stages.order(:id).last
    assert_equal "Etapa propia", stage.name
    assert_nil stage.stage_template_id
  end

  test "create sets the chosen color" do
    post project_project_stages_path(@project), params: {
      project_stage: { name: "Etapa propia", color: "#ff5733" }
    }
    stage = @project.project_stages.order(:id).last
    assert_equal "#ff5733", stage.color
  end

  test "create with a blank name redirects with an error" do
    assert_no_difference("@project.project_stages.count") do
      post project_project_stages_path(@project), params: { project_stage: { name: "" } }
    end
    assert_redirected_to project_path(@project)
  end

  test "update marks a stage not_applicable" do
    stage = @project.project_stages.first
    patch project_project_stage_path(@project, stage), params: { project_stage: { not_applicable: true } }
    assert stage.reload.not_applicable?
  end

  test "update reactivates a stage" do
    stage = @project.project_stages.first
    stage.update!(not_applicable: true)
    patch project_project_stage_path(@project, stage), params: { project_stage: { not_applicable: false } }
    assert_not stage.reload.not_applicable?
  end

  test "update ignores an attempt to change fields other than not_applicable" do
    stage = @project.project_stages.first
    original_name = stage.name
    patch project_project_stage_path(@project, stage), params: {
      project_stage: { not_applicable: true, name: "Nombre hackeado" }
    }
    stage.reload
    assert stage.not_applicable?
    assert_equal original_name, stage.name
  end

  test "create is blocked for a visor without edit access" do
    sign_in users(:maria)
    assert_no_difference("@project.project_stages.count") do
      post project_project_stages_path(@project), params: { project_stage: { name: "Intento" } }
    end
    assert_redirected_to project_path(@project)
  end

  test "update is blocked for a visor without edit access" do
    stage = @project.project_stages.first
    sign_in users(:maria)
    patch project_project_stage_path(@project, stage), params: { project_stage: { not_applicable: true } }
    assert_not stage.reload.not_applicable?
  end
end
