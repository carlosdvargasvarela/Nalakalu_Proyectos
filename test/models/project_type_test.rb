require "test_helper"

class ProjectTypeTest < ActiveSupport::TestCase
  test "valid with name and slug" do
    project_type = ProjectType.new(name: "Instalaciones", slug: "instalaciones")
    assert project_type.valid?
  end

  test "invalid without name" do
    project_type = ProjectType.new(slug: "instalaciones")
    assert_not project_type.valid?
  end

  test "invalid with duplicate slug" do
    ProjectType.create!(name: "Instalaciones", slug: "instalaciones")
    dup = ProjectType.new(name: "Otro", slug: "instalaciones")
    assert_not dup.valid?
  end
end
