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
end
