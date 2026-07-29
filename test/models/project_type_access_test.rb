require "test_helper"

class ProjectTypeAccessTest < ActiveSupport::TestCase
  test "valid with user and project_type" do
    access = ProjectTypeAccess.new(user: users(:carla), project_type: project_types(:instalaciones))
    assert access.valid?
  end

  test "invalid with a duplicate user/project_type pair" do
    ProjectTypeAccess.create!(user: users(:carla), project_type: project_types(:instalaciones), can_edit: true)
    dup = ProjectTypeAccess.new(user: users(:carla), project_type: project_types(:instalaciones))
    assert_not dup.valid?
  end

  test "can_edit defaults to false" do
    access = ProjectTypeAccess.create!(user: users(:carla), project_type: project_types(:instalaciones))
    assert_equal false, access.can_edit
  end
end
