require "test_helper"

class ProjectResponsiblesControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:juan) }
  setup do
    @project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
  end

  test "create adds a project-wide assignment" do
    assert_difference("@project.project_responsibles.count", 1) do
      post project_project_responsibles_path(@project), params: {
        project_responsible: { responsible_id: responsibles(:ana_gomez).id, responsible_type_id: responsible_types(:instalador).id }
      }
    end
    assert_redirected_to project_path(@project)
    assert @project.project_responsibles.last.project_wide?
  end

  test "create adds a stage-scoped assignment" do
    stage = @project.project_stages.first
    post project_project_responsibles_path(@project), params: {
      project_responsible: {
        responsible_id: responsibles(:ana_gomez).id, responsible_type_id: responsible_types(:instalador).id,
        project_stage_id: stage.id
      }
    }
    assert_equal stage, @project.project_responsibles.last.project_stage
  end

  test "create with an invalid combination re-renders the project with an error" do
    ProjectResponsible.create!(project: @project, responsible: responsibles(:ana_gomez), responsible_type: responsible_types(:instalador))
    assert_no_difference("@project.project_responsibles.count") do
      post project_project_responsibles_path(@project), params: {
        project_responsible: { responsible_id: responsibles(:ana_gomez).id, responsible_type_id: responsible_types(:instalador).id }
      }
    end
    assert_redirected_to project_path(@project)
  end

  test "destroy removes an assignment" do
    pr = ProjectResponsible.create!(project: @project, responsible: responsibles(:ana_gomez), responsible_type: responsible_types(:instalador))
    assert_difference("@project.project_responsibles.count", -1) do
      delete project_project_responsible_path(@project, pr)
    end
  end

  test "visor without edit access cannot create an assignment" do
    sign_in users(:maria)
    assert_no_difference("@project.project_responsibles.count") do
      post project_project_responsibles_path(@project), params: {
        project_responsible: { responsible_id: responsibles(:ana_gomez).id, responsible_type_id: responsible_types(:instalador).id }
      }
    end
    assert_redirected_to root_path
  end
end
