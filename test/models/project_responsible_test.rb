require "test_helper"

class ProjectResponsibleTest < ActiveSupport::TestCase
  setup do
    @project_type = project_types(:instalaciones)
    @responsible_type = ResponsibleType.create!(project_type: @project_type, name: "Instalador")
    @responsible = Responsible.create!(name: "Ana Gómez")
    ResponsibleProjectType.create!(responsible: @responsible, project_type: @project_type, responsible_type: @responsible_type)
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

  test "invalid when the responsible is configured with a different responsible_type for this project_type" do
    supervisor_type = ResponsibleType.create!(project_type: @project_type, name: "Supervisor")
    pr = ProjectResponsible.new(project: @project, responsible: @responsible, responsible_type: supervisor_type)
    assert_not pr.valid?
    assert_includes pr.errors[:responsible].join, "tipo de responsable"
  end

  test "a responsible can be a different type in a different project_type" do
    other_project_type = ProjectType.create!(name: "Mantenimiento", slug: "mantenimiento")
    other_responsible_type = ResponsibleType.create!(project_type: other_project_type, name: "Supervisor")
    ResponsibleProjectType.create!(responsible: @responsible, project_type: other_project_type, responsible_type: other_responsible_type)
    other_project = Project.create!(project_type: other_project_type, name: "Planta Sur", custom_fields: {})

    pr = ProjectResponsible.new(project: other_project, responsible: @responsible, responsible_type: other_responsible_type)
    assert pr.valid?
  end

  test "creating an assignment snapshots the responsible's name and color" do
    pr = ProjectResponsible.create!(project: @project, responsible: @responsible, responsible_type: @responsible_type)
    assert_equal @responsible.name, pr.responsible_name
    assert_equal @responsible.color, pr.responsible_color
  end

  test "renaming the responsible resyncs the snapshot on existing assignments" do
    pr = ProjectResponsible.create!(project: @project, responsible: @responsible, responsible_type: @responsible_type)
    @responsible.update!(name: "Ana G.", color: "#123456")
    assert_equal "Ana G.", pr.reload.responsible_name
    assert_equal "#123456", pr.reload.responsible_color
  end

  test "changing project_stage on an existing assignment does not touch the snapshot" do
    pr = ProjectResponsible.create!(project: @project, responsible: @responsible, responsible_type: @responsible_type)
    original_name = pr.responsible_name
    stage = @project.project_stages.first
    pr.update!(project_stage: stage)
    assert_equal original_name, pr.reload.responsible_name
  end
end
