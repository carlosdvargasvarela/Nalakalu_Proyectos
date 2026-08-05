require "test_helper"

class ProjectTypeTest < ActiveSupport::TestCase
  test "valid with name and slug" do
    project_type = ProjectType.new(name: "Mantenimiento", slug: "mantenimiento")
    assert project_type.valid?
  end

  test "invalid without name" do
    project_type = ProjectType.new(slug: "mantenimiento")
    assert_not project_type.valid?
  end

  test "invalid with duplicate slug" do
    ProjectType.create!(name: "Reparaciones", slug: "reparaciones")
    dup = ProjectType.new(name: "Otro", slug: "reparaciones")
    assert_not dup.valid?
  end

  test "creating a project_type seeds three default log_entry_types" do
    project_type = ProjectType.create!(name: "Mantenimiento", slug: "mantenimiento")
    assert_equal ["Nota", "Incidencia", "Cambio"], project_type.log_entry_types.order(:id).pluck(:name)
  end

  test "require_stage_dates defaults to false" do
    project_type = ProjectType.create!(name: "Mantenimiento", slug: "mantenimiento")
    assert_equal false, project_type.require_stage_dates
  end
end
