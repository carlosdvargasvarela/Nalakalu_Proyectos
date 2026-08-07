require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "status_label translates known statuses to Spanish" do
    assert_equal "Activo", status_label("active")
    assert_equal "Archivado", status_label("archived")
  end

  test "status_label returns the raw value for an unknown status" do
    assert_equal "weird_status", status_label("weird_status")
  end

  test "status_badge renders a colored badge with the Spanish label" do
    assert_match(/badge bg-success/, status_badge("active"))
    assert_match(/Activo/, status_badge("active"))
    assert_match(/badge bg-secondary/, status_badge("archived"))
    assert_match(/Archivado/, status_badge("archived"))
  end

  test "status_badge falls back to a neutral badge for an unknown status" do
    assert_match(/badge bg-light text-dark/, status_badge("weird_status"))
    assert_match(/weird_status/, status_badge("weird_status"))
  end

  test "progress_status_badge renders the right label and color for each state" do
    assert_match(/badge bg-secondary/, progress_status_badge("sin_iniciar"))
    assert_match(/Sin iniciar/, progress_status_badge("sin_iniciar"))
    assert_match(/badge bg-info/, progress_status_badge("iniciado"))
    assert_match(/Iniciado/, progress_status_badge("iniciado"))
    assert_match(/badge bg-success/, progress_status_badge("finalizado"))
    assert_match(/Finalizado/, progress_status_badge("finalizado"))
  end

  test "overdue_badge renders a red Vencido badge" do
    assert_match(/badge bg-danger/, overdue_badge)
    assert_match(/Vencido/, overdue_badge)
  end

  test "pending_stage_dates_count counts visible projects with an undated stage, only for types that require dates" do
    project_types(:instalaciones).update!(require_stage_dates: true)
    pending = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    complete = Project.create!(project_type: project_types(:instalaciones), name: "Torre Sur", custom_fields: {})
    complete.project_stages.each { |stage| stage.update!(start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 1, 10)) }

    assert_equal 1, pending_stage_dates_count(users(:juan))
  end

  test "pending_stage_dates_count counts visible projects with an undated stage, for types with auto duration enabled too" do
    field = FieldDefinition.create!(project_type: project_types(:instalaciones), key: "cantidad", label: "Cantidad", data_type: "number", position: 10)
    project_types(:instalaciones).update!(auto_stage_duration_enabled: true, duration_reference_field_definition: field)
    pending = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: { cantidad: "10" })
    complete = Project.create!(project_type: project_types(:instalaciones), name: "Torre Sur", custom_fields: { cantidad: "10" })
    complete.project_stages.each { |stage| stage.update!(start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 1, 10)) }

    assert_equal 1, pending_stage_dates_count(users(:juan))
  end

  test "pending_stage_dates_count ignores project types that don't require dates" do
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})

    assert_equal 0, pending_stage_dates_count(users(:juan))
  end
end
