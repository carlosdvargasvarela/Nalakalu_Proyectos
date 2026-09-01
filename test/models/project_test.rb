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

  test "start_date and end_date ignore a stage marked not_applicable" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    stages = project.project_stages.order(:id).to_a
    stages[0].update!(start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 1, 10))
    stages[1].update!(start_date: Date.new(2026, 6, 1), end_date: Date.new(2026, 6, 10), not_applicable: true)

    assert_equal Date.new(2026, 1, 1), project.start_date
    assert_equal Date.new(2026, 1, 10), project.end_date
  end

  test "find_stage ignores a stage with a matching name marked not_applicable" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    stage = project.project_stages.order(:id).first
    stage.update!(not_applicable: true)

    assert_nil project.find_stage(stage.name)
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

  test "current_stage ignores a stage marked not_applicable" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    stages = project.project_stages.order(:id).to_a
    stages.last.update!(progress_percent: 50, not_applicable: true)

    assert_equal stages.first, project.current_stage
  end

  test "representative_responsible_for prefers the project-wide assignment over a stage-scoped one" do
    project = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: {})
    stage = project.project_stages.first
    instalador = responsible_types(:instalador)
    ProjectResponsible.create!(project: project, responsible: responsibles(:ana_gomez), responsible_type: instalador, project_stage: stage)
    ProjectResponsible.create!(project: project, responsible: responsibles(:pedro_responsable), responsible_type: instalador)

    assert_equal responsibles(:pedro_responsable), project.responsible_for(instalador)
  end

  test "representative_responsible_for falls back to a stage-scoped assignment when there is no project-wide one" do
    project = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: {})
    stage = project.project_stages.first
    instalador = responsible_types(:instalador)
    ProjectResponsible.create!(project: project, responsible: responsibles(:ana_gomez), responsible_type: instalador, project_stage: stage)

    assert_equal responsibles(:ana_gomez), project.responsible_for(instalador)
  end

  test "representative_responsible_for returns nil when the project has no assignment of that type" do
    project = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: {})
    assert_nil project.responsible_for(responsible_types(:instalador))
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

  test "progress_status and progress_percent with stage_name reflect only that stage, not the whole project" do
    project = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: {})
    stages = project.project_stages.order(:id).to_a
    stages[0].update!(progress_percent: 100)
    stages[1].update!(progress_percent: 40)

    project.reload
    assert_equal "finalizado", project.progress_status(stage_name: stages[0].name)
    assert_equal 100, project.progress_percent(stage_name: stages[0].name)
    assert_equal "iniciado", project.progress_status(stage_name: stages[1].name)
    assert_equal 40, project.progress_percent(stage_name: stages[1].name)
    assert_not_equal project.progress_status(stage_name: stages[0].name), project.progress_status
  end

  test "progress_percent and progress_status ignore a stage marked not_applicable" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    stages = project.project_stages.order(:id).to_a
    stages.each { |s| s.update!(progress_percent: 100) }
    stages.last.update!(progress_percent: 0, not_applicable: true)

    assert_equal 100, project.progress_percent
    assert_equal "finalizado", project.progress_status
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

  test "stages_missing_dates returns only stages without both dates set" do
    project = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: {})
    dated, undated = project.project_stages.order(:id).first(2)
    dated.update!(start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 1, 10))

    missing = project.stages_missing_dates

    assert_includes missing, undated
    assert_not_includes missing, dated
  end

  test "stages_missing_dates treats a stage with only one date set as missing" do
    project = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: {})
    stage = project.project_stages.order(:id).first
    stage.update!(start_date: Date.new(2026, 1, 1), end_date: nil)

    assert_includes project.stages_missing_dates, stage
  end

  test "stages_missing_dates ignores a stage marked not_applicable" do
    project = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: {})
    stage = project.project_stages.order(:id).first
    stage.update!(not_applicable: true)

    assert_not_includes project.stages_missing_dates, stage
  end

  test "apply_auto_duration! sets sequential dates per stage_template when a profile matches" do
    field = FieldDefinition.create!(project_type: @project_type, key: "cantidad", label: "Cantidad", data_type: "number", position: 10)
    @project_type.update!(auto_stage_duration_enabled: true, duration_reference_field_definition: field)
    diseno = stage_templates(:diseno_aprobacion)
    revision = stage_templates(:revision_inicial)
    DurationProfile.create!(
      project_type: @project_type, operator: "between", min_value: 100, max_value: 500,
      durations: { diseno.id.to_s => 5, revision.id.to_s => 3 }
    )
    project = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: { "cantidad" => "300" })

    assert project.apply_auto_duration!(Date.new(2026, 1, 1))

    diseno_stage = project.project_stages.find_by(stage_template: diseno)
    revision_stage = project.project_stages.find_by(stage_template: revision)
    assert_equal Date.new(2026, 1, 1), diseno_stage.start_date
    assert_equal Date.new(2026, 1, 5), diseno_stage.end_date
    assert_equal Date.new(2026, 1, 6), revision_stage.start_date
    assert_equal Date.new(2026, 1, 8), revision_stage.end_date
  end

  test "apply_auto_duration! leaves a stage without dates when the profile has no duration for it" do
    field = FieldDefinition.create!(project_type: @project_type, key: "cantidad", label: "Cantidad", data_type: "number", position: 10)
    @project_type.update!(auto_stage_duration_enabled: true, duration_reference_field_definition: field)
    diseno = stage_templates(:diseno_aprobacion)
    revision = stage_templates(:revision_inicial)
    DurationProfile.create!(project_type: @project_type, operator: "between", min_value: 100, max_value: 500, durations: { diseno.id.to_s => 5 })
    project = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: { "cantidad" => "300" })

    project.apply_auto_duration!(Date.new(2026, 1, 1))

    revision_stage = project.project_stages.find_by(stage_template: revision)
    assert_nil revision_stage.start_date
  end

  test "apply_auto_duration! returns false when no profile matches" do
    field = FieldDefinition.create!(project_type: @project_type, key: "cantidad", label: "Cantidad", data_type: "number", position: 10)
    @project_type.update!(auto_stage_duration_enabled: true, duration_reference_field_definition: field)
    DurationProfile.create!(project_type: @project_type, operator: "greater_than", min_value: 1000)
    project = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: { "cantidad" => "5" })

    assert_not project.apply_auto_duration!(Date.new(2026, 1, 1))
    assert_nil project.project_stages.first.start_date
  end

  test "apply_auto_duration! skips a stage marked not_applicable" do
    field = FieldDefinition.create!(project_type: @project_type, key: "cantidad", label: "Cantidad", data_type: "number", position: 10)
    @project_type.update!(auto_stage_duration_enabled: true, duration_reference_field_definition: field)
    diseno = stage_templates(:diseno_aprobacion)
    revision = stage_templates(:revision_inicial)
    DurationProfile.create!(
      project_type: @project_type, operator: "between", min_value: 100, max_value: 500,
      durations: { diseno.id.to_s => 5, revision.id.to_s => 3 }
    )
    project = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: { "cantidad" => "300" })
    diseno_stage = project.project_stages.find_by(stage_template: diseno)
    diseno_stage.update!(not_applicable: true)

    assert project.apply_auto_duration!(Date.new(2026, 1, 1))

    assert_nil diseno_stage.reload.start_date
  end

  test "matching_duration_profile respects priority order (position ascending)" do
    field = FieldDefinition.create!(project_type: @project_type, key: "cantidad", label: "Cantidad", data_type: "number", position: 10)
    @project_type.update!(auto_stage_duration_enabled: true, duration_reference_field_definition: field)
    broad = DurationProfile.create!(project_type: @project_type, operator: "greater_than", min_value: 100, position: 1)
    narrow = DurationProfile.create!(project_type: @project_type, operator: "between", min_value: 100, max_value: 200, position: 0)
    project = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: { "cantidad" => "150" })

    assert_equal narrow, project.matching_duration_profile
  end

  test "creating a project with auto_duration_start_date computes stage dates via build_stages_from_template" do
    field = FieldDefinition.create!(project_type: @project_type, key: "cantidad", label: "Cantidad", data_type: "number", position: 10)
    @project_type.update!(auto_stage_duration_enabled: true, duration_reference_field_definition: field)
    diseno = stage_templates(:diseno_aprobacion)
    DurationProfile.create!(project_type: @project_type, operator: "greater_than", min_value: 1, durations: { diseno.id.to_s => 4 })

    project = Project.new(project_type: @project_type, name: "Torre Norte", custom_fields: { "cantidad" => "10" })
    project.auto_duration_start_date = "2026-02-01"
    project.save!

    diseno_stage = project.project_stages.find_by(stage_template: diseno)
    assert_equal Date.new(2026, 2, 1), diseno_stage.start_date
    assert_equal Date.new(2026, 2, 4), diseno_stage.end_date
  end

  test "creating a project without auto_duration_start_date leaves stages undated even when the type has auto duration enabled" do
    field = FieldDefinition.create!(project_type: @project_type, key: "cantidad", label: "Cantidad", data_type: "number", position: 10)
    @project_type.update!(auto_stage_duration_enabled: true, duration_reference_field_definition: field)
    diseno = stage_templates(:diseno_aprobacion)
    DurationProfile.create!(project_type: @project_type, operator: "greater_than", min_value: 1, durations: { diseno.id.to_s => 4 })

    project = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: { "cantidad" => "10" })

    assert_nil project.project_stages.find_by(stage_template: diseno).start_date
  end

  test "pending_auto_duration_start_date? is true when the first stage_template's stage has no start_date" do
    field = FieldDefinition.create!(project_type: @project_type, key: "cantidad", label: "Cantidad", data_type: "number", position: 10)
    @project_type.update!(auto_stage_duration_enabled: true, duration_reference_field_definition: field)
    project = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: {})

    assert project.pending_auto_duration_start_date?
  end

  test "pending_auto_duration_start_date? is false when the first stage is marked not_applicable" do
    field = FieldDefinition.create!(project_type: @project_type, key: "cantidad", label: "Cantidad", data_type: "number", position: 10)
    @project_type.update!(auto_stage_duration_enabled: true, duration_reference_field_definition: field)
    project = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: {})
    first_template = project.project_type.stage_templates.min_by(&:position)
    project.project_stages.find_by(stage_template_id: first_template.id).update!(not_applicable: true)

    assert_not project.pending_auto_duration_start_date?
  end

  test "pending_auto_duration_start_date? is false when the type doesn't have auto duration enabled" do
    project = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: {})
    assert_not project.pending_auto_duration_start_date?
  end

  test "pending_auto_duration_start_date? is false once the first stage already has a start_date" do
    field = FieldDefinition.create!(project_type: @project_type, key: "cantidad", label: "Cantidad", data_type: "number", position: 10)
    @project_type.update!(auto_stage_duration_enabled: true, duration_reference_field_definition: field)
    project = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: {})
    first_template = @project_type.stage_templates.min_by(&:position)
    project.project_stages.find_by(stage_template: first_template).update!(start_date: Date.new(2026, 1, 1))

    assert_not project.pending_auto_duration_start_date?
  end
end
