require "test_helper"

class Admin::ResponsiblesControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:juan) }

  test "index lists responsibles" do
    get admin_responsibles_path
    assert_response :success
    assert_select "body", /Ana Gómez/
  end

  test "create adds a new responsible" do
    assert_difference("Responsible.count", 1) do
      post admin_responsibles_path, params: { responsible: { name: "Nuevo Responsable" } }
    end
    assert_redirected_to admin_responsibles_path
  end

  test "create with blank name re-renders form with error" do
    assert_no_difference("Responsible.count") do
      post admin_responsibles_path, params: { responsible: { name: "" } }
    end
    assert_response :unprocessable_entity
  end

  test "create can link a user with no existing responsible" do
    unlinked_user = User.create!(email: "libre@example.com", password: "password123", role: "responsable")
    post admin_responsibles_path, params: { responsible: { name: "Nuevo", user_id: unlinked_user.id } }
    assert_equal unlinked_user, Responsible.order(:id).last.user
  end

  test "update changes the responsible's name and color" do
    responsible = responsibles(:ana_gomez)
    patch admin_responsible_path(responsible), params: { responsible: { name: "Ana G. Actualizada", color: "#f60404" } }
    assert_redirected_to admin_responsibles_path
    responsible.reload
    assert_equal "Ana G. Actualizada", responsible.name
    assert_equal "#f60404", responsible.color
  end

  test "destroy removes a responsible" do
    responsible = Responsible.create!(name: "Temporal")
    assert_difference("Responsible.count", -1) do
      delete admin_responsible_path(responsible)
    end
  end

  test "new and edit show the submit button in Spanish" do
    get new_admin_responsible_path
    assert_response :success
    assert_select "input[value=?]", "Crear Responsable"

    get edit_admin_responsible_path(responsibles(:ana_gomez))
    assert_response :success
    assert_select "input[value=?]", "Actualizar Responsable"
  end

  test "edit's user select offers unlinked users plus the currently linked one" do
    linked_elsewhere = User.create!(email: "otro-vinculado@example.com", password: "password123", role: "responsable")
    Responsible.create!(name: "Ya Vinculado", user: linked_elsewhere)
    unlinked = User.create!(email: "libre@example.com", password: "password123", role: "responsable")

    get edit_admin_responsible_path(responsibles(:ana_gomez))
    assert_response :success
    assert_select "select#responsible_user_id option[value=?]", unlinked.id.to_s
    assert_select "select#responsible_user_id option[value=?]", linked_elsewhere.id.to_s, count: 0
  end

  test "create with responsible_project_types_attributes enables the responsible for those types" do
    other_type = ProjectType.create!(name: "Mantenimiento", slug: "mantenimiento")
    other_responsible_type = ResponsibleType.create!(project_type: other_type, name: "Supervisor")
    post admin_responsibles_path, params: {
      responsible: {
        name: "Nuevo",
        responsible_project_types_attributes: {
          "0" => { project_type_id: project_types(:instalaciones).id, responsible_type_id: responsible_types(:instalador).id },
          "1" => { project_type_id: other_type.id, responsible_type_id: other_responsible_type.id },
        },
      },
    }
    created = Responsible.order(:id).last
    assert_equal [project_types(:instalaciones), other_type].sort_by(&:id), created.project_types.sort_by(&:id)
  end

  test "update can unenable every project type, leaving none" do
    responsible = responsibles(:ana_gomez)
    link = responsible.responsible_project_types.first

    patch admin_responsible_path(responsible), params: {
      responsible: {
        name: responsible.name,
        responsible_project_types_attributes: { "0" => { id: link.id, project_type_id: link.project_type_id, responsible_type_id: "" } },
      },
    }

    assert_equal [], responsible.reload.project_types
  end

  test "edit shows a select per project type, pre-filled for the ones already enabled" do
    get edit_admin_responsible_path(responsibles(:ana_gomez))
    assert_response :success
    assert_select "select[name=?] option[selected][value=?]",
      "responsible[responsible_project_types_attributes][0][responsible_type_id]", responsible_types(:instalador).id.to_s
  end

  test "new shows the Usuario vinculado select marked for TomSelect" do
    get new_admin_responsible_path
    assert_response :success
    assert_select "select[data-controller=?]#responsible_user_id", "tom-select"
  end

  test "gerente sees the list without create or delete buttons" do
    sign_in users(:carla)
    get admin_responsibles_path
    assert_response :success
    assert_select "a[href=?]", new_admin_responsible_path, count: 0
    assert_select "form[action=?]", admin_responsible_path(responsibles(:ana_gomez)), count: 0
  end

  test "gerente edit form shows only name and color" do
    sign_in users(:carla)
    get edit_admin_responsible_path(responsibles(:ana_gomez))
    assert_response :success
    assert_select "input[name='responsible[name]']"
    assert_select "input[name='responsible[color]']"
    assert_select "select[name='responsible[user_id]']", count: 0
  end

  test "gerente update changes only name and color" do
    sign_in users(:carla)
    responsible = responsibles(:ana_gomez)
    other_user = User.create!(email: "otro@example.com", password: "password123", role: "responsable")
    patch admin_responsible_path(responsible), params: { responsible: { name: "Ana Gerente", color: "#123456", user_id: other_user.id } }
    assert_redirected_to admin_responsibles_path
    responsible.reload
    assert_equal "Ana Gerente", responsible.name
    assert_equal "#123456", responsible.color
    assert_not_equal other_user.id, responsible.user_id
  end

  test "gerente cannot create or delete responsibles" do
    sign_in users(:carla)
    assert_no_difference("Responsible.count") do
      post admin_responsibles_path, params: { responsible: { name: "X" } }
      delete admin_responsible_path(responsibles(:ana_gomez))
    end
    assert_redirected_to root_path
  end
end
