require "test_helper"

class ProjectStageTest < ActiveSupport::TestCase
  test "creating a project builds one stage per stage_template, in order" do
    project = Project.create!(
      project_type: project_types(:instalaciones),
      name: "Instalación Torre Norte",
      custom_fields: {}
    )

    names = project.project_stages.order(:id).map(&:name)
    assert_equal ["Diseño-Aprobación", "Revisión Inicial", "Producción", "Entrega", "Instalación"], names
  end

  test "editing a stage_template does not change existing project_stages" do
    project = Project.create!(
      project_type: project_types(:instalaciones),
      name: "Instalación Torre Norte",
      custom_fields: {}
    )
    template = stage_templates(:produccion)
    template.update!(name: "Producción v2")

    stage = project.project_stages.find_by(stage_template_id: template.id)
    assert_equal "Producción", stage.name
  end

  test "deleting a stage_template does not delete existing project_stages" do
    project = Project.create!(
      project_type: project_types(:instalaciones),
      name: "Instalación Torre Norte",
      custom_fields: {}
    )
    template = stage_templates(:produccion)
    template.destroy!

    stage = project.project_stages.find_by(name: "Producción")
    assert stage.present?
    assert_nil stage.reload.stage_template_id
  end

  test "valid with and without an assigned user" do
    project = Project.create!(
      project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {}
    )
    stage = project.project_stages.first

    stage.user = users(:juan)
    assert stage.valid?, stage.errors.full_messages.to_s

    stage.user = nil
    assert stage.valid?, stage.errors.full_messages.to_s
  end
end
