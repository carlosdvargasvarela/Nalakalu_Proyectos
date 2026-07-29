require "test_helper"

class ResponsibleTypeTest < ActiveSupport::TestCase
  test "valid with name and project_type" do
    type = ResponsibleType.new(project_type: project_types(:instalaciones), name: "Instalador")
    assert type.valid?
  end

  test "invalid without name" do
    type = ResponsibleType.new(project_type: project_types(:instalaciones))
    assert_not type.valid?
  end

  test "invalid with a duplicate name within the same project_type" do
    ResponsibleType.create!(project_type: project_types(:instalaciones), name: "Instalador")
    dup = ResponsibleType.new(project_type: project_types(:instalaciones), name: "Instalador")
    assert_not dup.valid?
  end

  test "valid with the same name in a different project_type" do
    ResponsibleType.create!(project_type: project_types(:instalaciones), name: "Instalador")
    other_type = ProjectType.create!(name: "Mantenimiento", slug: "mantenimiento")
    assert ResponsibleType.new(project_type: other_type, name: "Instalador").valid?
  end
end
