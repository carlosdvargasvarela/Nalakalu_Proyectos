require "test_helper"

class ProjectAccessTest < ActiveSupport::TestCase
  setup do
    @project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
  end

  test "valid with user and project" do
    access = ProjectAccess.new(user: users(:maria), project: @project)
    assert access.valid?
  end

  test "invalid with a duplicate user/project pair" do
    ProjectAccess.create!(user: users(:maria), project: @project)
    dup = ProjectAccess.new(user: users(:maria), project: @project)
    assert_not dup.valid?
  end

  test "can_edit defaults to false" do
    access = ProjectAccess.create!(user: users(:maria), project: @project)
    assert_equal false, access.can_edit
  end
end
