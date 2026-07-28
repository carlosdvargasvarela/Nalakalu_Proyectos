require "test_helper"

class Admin::UsersControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:juan) }

  test "index lists users" do
    get admin_users_path
    assert_response :success
    assert_select "body", /carla@example.com/
  end

  test "create adds a new user with a role" do
    assert_difference("User.count", 1) do
      post admin_users_path, params: {
        user: { email: "nuevo@example.com", password: "password123", password_confirmation: "password123", role: "gerente" }
      }
    end
    assert_redirected_to admin_users_path
    assert User.find_by(email: "nuevo@example.com").gerente?
  end

  test "create with blank email re-renders form with error" do
    assert_no_difference("User.count") do
      post admin_users_path, params: { user: { email: "", password: "password123", password_confirmation: "password123", role: "visor" } }
    end
    assert_response :unprocessable_entity
  end

  test "update changes the role without requiring a password" do
    patch admin_user_path(users(:maria)), params: { user: { email: users(:maria).email, role: "gerente" } }
    assert_redirected_to admin_users_path
    assert users(:maria).reload.gerente?
  end

  test "update with a password changes it" do
    patch admin_user_path(users(:maria)), params: {
      user: { email: users(:maria).email, role: "visor", password: "nuevapass123", password_confirmation: "nuevapass123" }
    }
    assert_redirected_to admin_users_path
    assert users(:maria).reload.valid_password?("nuevapass123")
  end

  test "update assigns project access from the checkboxes" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    patch admin_user_path(users(:maria)), params: {
      user: { email: users(:maria).email, role: "visor" },
      sync_project_access: "1",
      project_access: { project.id.to_s => { "view" => "1", "edit" => "0" } }
    }
    assert users(:maria).reload.can_view_project?(project)
    assert_not users(:maria).can_edit_project?(project)
  end

  test "update without the access-form marker does not touch existing project access" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    ProjectAccess.create!(user: users(:maria), project: project)

    patch admin_user_path(users(:maria)), params: { user: { email: users(:maria).email, role: "visor" } }

    assert users(:maria).reload.can_view_project?(project)
  end

  test "destroy removes a user" do
    target = User.create!(email: "temporal@example.com", password: "password123", role: "visor")
    assert_difference("User.count", -1) do
      delete admin_user_path(target)
    end
  end

  test "gerente and visor cannot access admin users" do
    sign_in users(:carla)
    get admin_users_path
    assert_redirected_to root_path

    sign_in users(:maria)
    get admin_users_path
    assert_redirected_to root_path
  end
end
