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
end
