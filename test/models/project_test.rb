require "test_helper"

class ProjectTest < ActiveSupport::TestCase
  setup do
    @project_type = project_types(:instalaciones)
  end

  test "valid with correct custom_fields types" do
    project = Project.new(
      project_type: @project_type,
      name: "Instalación Torre Norte",
      custom_fields: { "cliente" => "Acme S.A." }
    )
    assert project.valid?, project.errors.full_messages.to_s
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

  test "valid with correct values for the new data types" do
    FieldDefinition.create!(project_type: @project_type, key: "cantidad", label: "Cantidad", data_type: "number", position: 10)
    FieldDefinition.create!(project_type: @project_type, key: "monto", label: "Monto", data_type: "currency", position: 11)
    FieldDefinition.create!(project_type: @project_type, key: "notas", label: "Notas", data_type: "textarea", position: 12)
    FieldDefinition.create!(project_type: @project_type, key: "permiso", label: "Permiso", data_type: "boolean", position: 13)

    project = Project.new(
      project_type: @project_type, name: "Torre Norte",
      custom_fields: { "cantidad" => "3", "monto" => "1500.50", "notas" => "Cliente pidió instalación urgente", "permiso" => "true" }
    )
    assert project.valid?, project.errors.full_messages.to_s
  end

  test "invalid when a number or currency field isn't numeric" do
    FieldDefinition.create!(project_type: @project_type, key: "cantidad", label: "Cantidad", data_type: "number", position: 10)
    project = Project.new(
      project_type: @project_type, name: "Torre Norte", custom_fields: { "cantidad" => "no es un número" }
    )
    assert_not project.valid?
  end

  test "invalid when a boolean field isn't true or false" do
    FieldDefinition.create!(project_type: @project_type, key: "permiso", label: "Permiso", data_type: "boolean", position: 10)
    project = Project.new(
      project_type: @project_type, name: "Torre Norte", custom_fields: { "permiso" => "tal vez" }
    )
    assert_not project.valid?
  end

  test "valid when a boolean field is True or FALSE (case-insensitive)" do
    FieldDefinition.create!(project_type: @project_type, key: "permiso", label: "Permiso", data_type: "boolean", position: 10)
    project = Project.new(
      project_type: @project_type, name: "Torre Norte", custom_fields: { "permiso" => "True" }
    )
    assert project.valid?, project.errors.full_messages.to_s
  end

  test "valid when a textarea field is a plain string" do
    FieldDefinition.create!(project_type: @project_type, key: "notas", label: "Notas", data_type: "textarea", position: 10)
    project = Project.new(
      project_type: @project_type, name: "Torre Norte", custom_fields: { "notas" => "una nota larga" }
    )
    assert project.valid?, project.errors.full_messages.to_s
  end

  test "updating a project creates a paper_trail version with the acting user" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    PaperTrail.request(whodunnit: users(:juan).id.to_s) do
      project.update!(name: "Torre Norte 2")
    end

    version = project.versions.last
    assert_equal "update", version.event
    assert_equal users(:juan).id.to_s, version.whodunnit
  end

  test "visible_to returns all projects for admin and gerente" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    assert_includes Project.visible_to(users(:juan)), project
    assert_includes Project.visible_to(users(:carla)), project
  end

  test "visible_to returns only accessible projects for visor" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    other = Project.create!(project_type: project_types(:instalaciones), name: "Torre Sur", custom_fields: {})
    ProjectAccess.create!(user: users(:maria), project: project)

    visible = Project.visible_to(users(:maria))
    assert_includes visible, project
    assert_not_includes visible, other
  end

  test "visible_to also returns a visor's projects via their linked responsible, without a ProjectAccess" do
    assigned = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    unassigned = Project.create!(project_type: project_types(:instalaciones), name: "Torre Sur", custom_fields: {})
    visor = User.create!(email: "visor-instalador@example.com", password: "password123", role: "visor")
    responsible = Responsible.create!(name: "Visor Instalador", user: visor)
    ResponsibleProjectType.create!(responsible: responsible, project_type: project_types(:instalaciones), responsible_type: responsible_types(:instalador))
    ProjectResponsible.create!(project: assigned, responsible: responsible, responsible_type: responsible_types(:instalador))

    visible = Project.visible_to(visor)
    assert_includes visible, assigned
    assert_not_includes visible, unassigned
  end

  test "visible_to combines a visor's ProjectAccess and responsible-linked projects without duplicates" do
    via_access = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    via_responsible = Project.create!(project_type: project_types(:instalaciones), name: "Torre Sur", custom_fields: {})
    visor = User.create!(email: "visor-ambos@example.com", password: "password123", role: "visor")
    responsible = Responsible.create!(name: "Visor Ambos", user: visor)
    ResponsibleProjectType.create!(responsible: responsible, project_type: project_types(:instalaciones), responsible_type: responsible_types(:instalador))
    ProjectAccess.create!(user: visor, project: via_access)
    ProjectResponsible.create!(project: via_responsible, responsible: responsible, responsible_type: responsible_types(:instalador))

    visible = Project.visible_to(visor).to_a
    assert_equal [via_access, via_responsible].sort_by(&:id), visible.sort_by(&:id)
  end

  test "visible_to a responsable only returns projects with an assignment" do
    assigned = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: {})
    Project.create!(project_type: @project_type, name: "Torre Sur", custom_fields: {})
    responsable = users(:pedro)
    ProjectResponsible.create!(
      project: assigned, responsible: responsable.responsible, responsible_type: responsible_types(:instalador)
    )

    assert_equal [assigned], Project.visible_to(responsable).to_a
  end

  test "visible_to a responsable with no linked Responsible returns none" do
    unlinked = User.create!(email: "sin-vinculo@example.com", password: "password123", role: "responsable")
    Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: {})

    assert_equal [], Project.visible_to(unlinked).to_a
  end
end
