require "test_helper"

class Admin::StageTemplatesControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:juan) }
  setup { @project_type = project_types(:instalaciones) }

  test "create adds a stage template to the project type" do
    assert_difference("@project_type.stage_templates.count", 1) do
      post admin_project_type_stage_templates_path(@project_type), params: {
        stage_template: { name: "Postventa", position: 6 }
      }
    end
    assert_redirected_to admin_project_type_path(@project_type)
  end

  test "create with blank name re-renders form with error" do
    assert_no_difference("@project_type.stage_templates.count") do
      post admin_project_type_stage_templates_path(@project_type), params: {
        stage_template: { name: "", position: 6 }
      }
    end
    assert_response :unprocessable_entity
  end

  test "update saves the color" do
    stage = stage_templates(:entrega)
    patch admin_project_type_stage_template_path(@project_type, stage), params: {
      stage_template: { name: stage.name, position: stage.position, color: "#f60404" }
    }
    assert_redirected_to admin_project_type_path(@project_type)
    assert_equal "#f60404", stage.reload.color
  end

  test "destroy removes a stage template" do
    stage = stage_templates(:entrega)
    assert_difference("@project_type.stage_templates.count", -1) do
      delete admin_project_type_stage_template_path(@project_type, stage)
    end
  end
end
