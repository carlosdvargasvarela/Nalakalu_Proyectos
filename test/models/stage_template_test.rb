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

  test "valid with default color" do
    stage = StageTemplate.new(project_type: project_types(:instalaciones), name: "Producción", position: 3)
    assert stage.valid?
    assert_equal "#6c757d", stage.color
  end

  test "invalid with a malformed color" do
    stage = StageTemplate.new(
      project_type: project_types(:instalaciones), name: "Producción", position: 3, color: "blue"
    )
    assert_not stage.valid?
  end

  test "default_in_filter defaults to false" do
    stage = StageTemplate.new(project_type: project_types(:instalaciones), name: "Producción", position: 3)
    assert_equal false, stage.default_in_filter
  end

  test "marking one stage_template as default_in_filter clears any previous default in the same project_type" do
    entrega = stage_templates(:entrega)
    instalacion = stage_templates(:instalacion)

    entrega.update!(default_in_filter: true)
    assert entrega.reload.default_in_filter

    instalacion.update!(default_in_filter: true)
    assert instalacion.reload.default_in_filter
    assert_not entrega.reload.default_in_filter
  end

  test "marking a stage_template as default_in_filter doesn't affect a different project_type's default" do
    other_type = ProjectType.create!(name: "Mantenimiento", slug: "mantenimiento")
    other_stage = other_type.stage_templates.create!(name: "Revisión", position: 1, default_in_filter: true)

    stage_templates(:entrega).update!(default_in_filter: true)

    assert other_stage.reload.default_in_filter
  end
end
