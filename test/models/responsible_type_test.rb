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

  test "default_in_filter defaults to false" do
    type = ResponsibleType.new(project_type: project_types(:instalaciones), name: "Supervisor")
    assert_equal false, type.default_in_filter
  end

  test "marking one responsible_type as default_in_filter clears any previous default in the same project_type" do
    instalador = responsible_types(:instalador)
    disenador = responsible_types(:disenador)

    instalador.update!(default_in_filter: true)
    assert instalador.reload.default_in_filter

    disenador.update!(default_in_filter: true)
    assert disenador.reload.default_in_filter
    assert_not instalador.reload.default_in_filter
  end

  test "marking a responsible_type as default_in_filter doesn't affect a different project_type's default" do
    other_type = ProjectType.create!(name: "Mantenimiento", slug: "mantenimiento")
    other_responsible_type = other_type.responsible_types.create!(name: "Técnico", default_in_filter: true)

    responsible_types(:instalador).update!(default_in_filter: true)

    assert other_responsible_type.reload.default_in_filter
  end
end
