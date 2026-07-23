require "test_helper"

class StageTemplateTest < ActiveSupport::TestCase
  test "valid with name and position" do
    stage = StageTemplate.new(project_type: project_types(:instalaciones), name: "Producción", position: 3)
    assert stage.valid?
  end

  test "invalid without name" do
    stage = StageTemplate.new(project_type: project_types(:instalaciones), position: 3)
    assert_not stage.valid?
  end

  test "project_type orders stage_templates by position" do
    ordered = project_types(:instalaciones).stage_templates.map(&:name)
    assert_equal ["Diseño-Aprobación", "Revisión Inicial", "Producción", "Entrega", "Instalación"], ordered
  end
end
