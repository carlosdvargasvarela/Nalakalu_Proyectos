require "test_helper"

class ProjectTest < ActiveSupport::TestCase
  setup do
    @project_type = project_types(:instalaciones)
  end

  test "valid with correct custom_fields types" do
    project = Project.new(
      project_type: @project_type,
      name: "Instalación Torre Norte",
      custom_fields: { "cliente" => "Acme S.A.", "instalador" => installers(:juan_perez).id }
    )
    assert project.valid?, project.errors.full_messages.to_s
  end

  test "invalid when reference field points to a nonexistent installer" do
    project = Project.new(
      project_type: @project_type,
      name: "Instalación Torre Norte",
      custom_fields: { "cliente" => "Acme S.A.", "instalador" => 999_999 }
    )
    assert_not project.valid?
    assert_includes project.errors[:custom_fields].join, "Instalador"
  end

  test "invalid when text field is not a string" do
    project = Project.new(
      project_type: @project_type,
      name: "Instalación Torre Norte",
      custom_fields: { "cliente" => 12345 }
    )
    assert_not project.valid?
  end

  test "valid when a field is simply absent (not required)" do
    project = Project.new(
      project_type: @project_type,
      name: "Instalación Torre Norte",
      custom_fields: {}
    )
    assert project.valid?
  end

  test "valid when a field is blank string, as submitted by an empty form field" do
    project = Project.new(
      project_type: @project_type,
      name: "Instalación Torre Norte",
      custom_fields: { "cliente" => "Acme S.A.", "instalador" => "" }
    )
    assert project.valid?, project.errors.full_messages.to_s
  end

  test "start_date and end_date reflect the earliest and latest stage dates" do
    project = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: {})
    stages = project.project_stages.order(:id).to_a
    stages[0].update!(start_date: Date.new(2026, 1, 10), end_date: Date.new(2026, 1, 20))
    stages[1].update!(start_date: Date.new(2026, 1, 5), end_date: Date.new(2026, 1, 15))
    stages[2].update!(start_date: Date.new(2026, 2, 1), end_date: Date.new(2026, 2, 28))

    assert_equal Date.new(2026, 1, 5), project.start_date
    assert_equal Date.new(2026, 2, 28), project.end_date
    assert_equal [Date.new(2026, 1, 5), Date.new(2026, 2, 28)], project.gantt_window
  end

  test "gantt_window falls back to a one-week window from created_at when no stage has dates" do
    project = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: {})
    first, last = project.gantt_window
    assert_equal project.created_at.to_date, first
    assert_equal first + 7.days, last
  end

  test "current_stage is the most advanced started stage, or the first stage if none started" do
    project = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: {})
    stages = project.project_stages.order(:id).to_a
    assert_equal stages.first, project.current_stage

    stages[0].update!(progress_percent: 100)
    stages[1].update!(progress_percent: 40)
    assert_equal stages[1], project.reload.current_stage
  end

  test "project_stages_attributes updates existing stages without creating or destroying any" do
    project = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: {})
    stage = project.project_stages.order(:id).first

    assert_no_difference("project.project_stages.count") do
      project.update!(project_stages_attributes: { "0" => { id: stage.id, progress_percent: 75 } })
    end

    assert_equal 75, stage.reload.progress_percent
  end

  test "installer resolves the assigned Installer through the dynamic reference field" do
    project = Project.create!(
      project_type: @project_type, name: "Torre Norte",
      custom_fields: { "instalador" => installers(:juan_perez).id }
    )
    assert_equal installers(:juan_perez), project.installer
  end

  test "installer is nil when no installer has been assigned yet" do
    project = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: {})
    assert_nil project.installer
  end

  test "installer is nil when the assigned id no longer exists" do
    project = Project.new(
      project_type: @project_type, name: "Torre Norte",
      custom_fields: { "instalador" => 999_999 }
    )
    project.save!(validate: false)
    assert_nil project.installer
  end

  test "progress_status is sin_iniciar when every stage is at 0%" do
    project = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: {})
    assert_equal "sin_iniciar", project.progress_status
  end

  test "progress_status is iniciado when at least one stage has progress but not all are finished" do
    project = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: {})
    project.project_stages.order(:id).first.update!(progress_percent: 40)
    assert_equal "iniciado", project.reload.progress_status
  end

  test "progress_status is finalizado when every stage is at 100%" do
    project = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: {})
    project.project_stages.each { |stage| stage.update!(progress_percent: 100) }
    assert_equal "finalizado", project.reload.progress_status
  end

  test "project overdue? is true only when its end_date has passed and it isn't finalizado" do
    project = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: {})
    stages = project.project_stages.order(:id).to_a
    stages[0].update!(end_date: Date.current - 1.day, progress_percent: 50)

    assert project.reload.overdue?

    stages.each { |stage| stage.update!(progress_percent: 100) }
    assert_not project.reload.overdue?
  end

  test "project overdue? is false when it has no end_date yet" do
    project = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: {})
    assert_nil project.end_date
    assert_not project.overdue?
  end
end
