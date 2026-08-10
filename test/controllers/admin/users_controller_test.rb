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

  test "update applies an email change immediately without requiring reconfirmation" do
    user = users(:maria)
    patch admin_user_path(user), params: { user: { email: "maria-nueva@example.com", role: user.role } }
    user.reload
    assert_equal "maria-nueva@example.com", user.email
    assert_nil user.unconfirmed_email
  end

  test "update assigns project access from the checkboxes" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    patch admin_user_path(users(:carla)), params: {
      user: { email: users(:carla).email, role: "gerente" },
      sync_project_access: "1",
      project_access: { project.id.to_s => { "view" => "1", "edit" => "1" } }
    }
    assert users(:carla).reload.can_edit_project?(project)
  end

  test "edit renders successfully with the project access checkbox table" do
    get edit_admin_user_path(users(:maria))
    assert_response :success
  end

  test "update without the access-form marker does not touch existing project access" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    ProjectAccess.create!(user: users(:maria), project: project)

    patch admin_user_path(users(:maria)), params: { user: { email: users(:maria).email, role: "visor" } }

    assert users(:maria).reload.can_view_project?(project)
  end

  test "update assigns project type access from the checkboxes" do
    patch admin_user_path(users(:carla)), params: {
      user: { email: users(:carla).email, role: "gerente" },
      sync_project_access: "1",
      project_type_access: { project_types(:instalaciones).id.to_s => { "edit" => "1" } }
    }
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    assert users(:carla).reload.can_edit_project?(project)
  end

  test "update without the access-form marker does not touch existing project type access" do
    ProjectTypeAccess.create!(user: users(:carla), project_type: project_types(:instalaciones), can_edit: true)

    patch admin_user_path(users(:carla)), params: { user: { email: users(:carla).email, role: "gerente" } }

    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    assert users(:carla).reload.can_edit_project?(project)
  end

  test "edit exposes project types for the type-grants table" do
    get edit_admin_user_path(users(:maria))
    assert_response :success
  end

  test "edit renders the project type grants table and the project search box" do
    get edit_admin_user_path(users(:maria))
    assert_select "table#project-access-table"
    assert_select "input#project-access-search"
    assert_select "table", text: /Editar/, count: 2 # type-grants table + project table both have an "Editar" column
  end

  test "destroy removes a user" do
    target = User.create!(email: "temporal@example.com", password: "password123", role: "visor")
    assert_difference("User.count", -1) do
      delete admin_user_path(target)
    end
  end

  test "destroy does not remove a user who authored a log entry, and sets an alert" do
    target = User.create!(email: "temporal@example.com", password: "password123", role: "visor")
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    LogEntry.create!(project: project, user: target, log_entry_type: log_entry_types(:nota), body: "Nota de temporal")

    assert_no_difference("User.count") do
      delete admin_user_path(target)
    end
    assert_equal "No se puede eliminar: tiene notas de bitácora o etapas asignadas.", flash[:alert]
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
