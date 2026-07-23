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
end
