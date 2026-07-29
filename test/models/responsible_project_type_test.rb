require "test_helper"

class ResponsibleProjectTypeTest < ActiveSupport::TestCase
  test "valid with a responsible and a project_type" do
    ResponsibleProjectType.delete_all
    rpt = ResponsibleProjectType.new(responsible: responsibles(:ana_gomez), project_type: project_types(:instalaciones))
    assert rpt.valid?
  end

  test "invalid with a duplicate responsible/project_type pair" do
    ResponsibleProjectType.delete_all
    ResponsibleProjectType.create!(responsible: responsibles(:ana_gomez), project_type: project_types(:instalaciones))
    dup = ResponsibleProjectType.new(responsible: responsibles(:ana_gomez), project_type: project_types(:instalaciones))
    assert_not dup.valid?
  end
end
