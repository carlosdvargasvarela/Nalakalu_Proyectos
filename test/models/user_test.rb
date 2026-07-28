require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "defaults to visor role" do
    user = User.create!(email: "nuevo@example.com", password: "password123")
    assert user.visor?
  end

  test "role accepts admin, gerente, and visor" do
    assert User.new(role: "admin").admin?
    assert User.new(role: "gerente").gerente?
    assert User.new(role: "visor").visor?
  end

  test "admin can view and edit any project" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    assert users(:juan).can_view_project?(project)
    assert users(:juan).can_edit_project?(project)
  end

  test "gerente can view any project but only edit those with can_edit access" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    gerente = users(:carla)
    assert gerente.can_view_project?(project)
    assert_not gerente.can_edit_project?(project)

    ProjectAccess.create!(user: gerente, project: project, can_edit: true)
    assert gerente.can_edit_project?(project)
  end

  test "visor can only view projects with an access row, and never edits" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    visor = users(:maria)
    assert_not visor.can_view_project?(project)
    assert_not visor.can_edit_project?(project)

    ProjectAccess.create!(user: visor, project: project, can_edit: true)
    assert visor.can_view_project?(project)
    assert_not visor.can_edit_project?(project)
  end
end
