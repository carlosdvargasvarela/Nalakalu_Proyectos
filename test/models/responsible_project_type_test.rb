require "test_helper"

class ResponsibleProjectTypeTest < ActiveSupport::TestCase
  test "valid with a responsible, a project_type and a matching responsible_type" do
    ResponsibleProjectType.delete_all
    rpt = ResponsibleProjectType.new(
      responsible: responsibles(:ana_gomez), project_type: project_types(:instalaciones),
      responsible_type: responsible_types(:instalador)
    )
    assert rpt.valid?
  end

  test "invalid with a duplicate responsible/project_type pair" do
    ResponsibleProjectType.delete_all
    ResponsibleProjectType.create!(
      responsible: responsibles(:ana_gomez), project_type: project_types(:instalaciones),
      responsible_type: responsible_types(:instalador)
    )
    dup = ResponsibleProjectType.new(
      responsible: responsibles(:ana_gomez), project_type: project_types(:instalaciones),
      responsible_type: responsible_types(:instalador)
    )
    assert_not dup.valid?
  end

  test "invalid when responsible_type belongs to a different project_type" do
    ResponsibleProjectType.delete_all
    other_type = ProjectType.create!(name: "Mantenimiento", slug: "mantenimiento")
    foreign_responsible_type = ResponsibleType.create!(project_type: other_type, name: "Supervisor")
    rpt = ResponsibleProjectType.new(
      responsible: responsibles(:ana_gomez), project_type: project_types(:instalaciones),
      responsible_type: foreign_responsible_type
    )
    assert_not rpt.valid?
  end
end
