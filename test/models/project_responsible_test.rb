require "test_helper"

class ProjectResponsibleTest < ActiveSupport::TestCase
  setup do
    @project_type = project_types(:instalaciones)
    @responsible_type = ResponsibleType.create!(project_type: @project_type, name: "Instalador")
    @responsible = Responsible.create!(name: "Ana Gómez")
    ResponsibleProjectType.create!(responsible: @responsible, project_type: @project_type)
    @project = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: {})
  end

  test "invalid when the responsible is not enabled for the project's type" do
    ResponsibleProjectType.delete_all
    pr = ProjectResponsible.new(project: @project, responsible: @responsible, responsible_type: @responsible_type)
    assert_not pr.valid?
    assert_includes pr.errors[:responsible].join, "habilitado"
  end

  test "valid when the responsible is enabled for the project's type" do
    pr = ProjectResponsible.new(project: @project, responsible: @responsible, responsible_type: @responsible_type)
    assert pr.valid?
  end

  test "valid at project level (no stage)" do
    pr = ProjectResponsible.new(project: @project, responsible: @responsible, responsible_type: @responsible_type)
    assert pr.valid?
    assert pr.project_wide?
  end

  test "valid scoped to one of the project's stages" do
    stage = @project.project_stages.first
    pr = ProjectResponsible.new(project: @project, responsible: @responsible, responsible_type: @responsible_type, project_stage: stage)
    assert pr.valid?
    assert_not pr.project_wide?
  end

  test "invalid with a duplicate responsible/type/stage combination" do
    ProjectResponsible.create!(project: @project, responsible: @responsible, responsible_type: @responsible_type)
    dup = ProjectResponsible.new(project: @project, responsible: @responsible, responsible_type: @responsible_type)
    assert_not dup.valid?
  end

  test "valid with the same responsible/type at project level and at a specific stage" do
    ProjectResponsible.create!(project: @project, responsible: @responsible, responsible_type: @responsible_type)
    scoped = ProjectResponsible.new(
      project: @project, responsible: @responsible, responsible_type: @responsible_type,
      project_stage: @project.project_stages.first
    )
    assert scoped.valid?
  end

  test "invalid when project_stage belongs to a different project" do
    other_project = Project.create!(project_type: @project_type, name: "Torre Sur", custom_fields: {})
    pr = ProjectResponsible.new(
      project: @project, responsible: @responsible, responsible_type: @responsible_type,
      project_stage: other_project.project_stages.first
    )
    assert_not pr.valid?
  end

  test "invalid when responsible_type belongs to a different project_type" do
    other_type = ProjectType.create!(name: "Mantenimiento", slug: "mantenimiento")
    foreign_responsible_type = ResponsibleType.create!(project_type: other_type, name: "Instalador")
    pr = ProjectResponsible.new(project: @project, responsible: @responsible, responsible_type: foreign_responsible_type)
    assert_not pr.valid?
  end
end
