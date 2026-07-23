require "test_helper"

class Admin::InstallersControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:juan) }

  test "index lists installers" do
    get admin_installers_path
    assert_response :success
    assert_select "body", /Juan Pérez/
  end

  test "create adds a new installer" do
    assert_difference("Installer.count", 1) do
      post admin_installers_path, params: { installer: { name: "Ana Gómez" } }
    end
    assert_redirected_to admin_installers_path
  end

  test "create with blank name re-renders form with error" do
    assert_no_difference("Installer.count") do
      post admin_installers_path, params: { installer: { name: "" } }
    end
    assert_response :unprocessable_entity
  end

  test "update changes the installer's name" do
    installer = installers(:juan_perez)
    patch admin_installer_path(installer), params: { installer: { name: "Juan P. Actualizado" } }
    assert_redirected_to admin_installers_path
    assert_equal "Juan P. Actualizado", installer.reload.name
  end

  test "destroy removes an installer" do
    installer = Installer.create!(name: "Temporal")
    assert_difference("Installer.count", -1) do
      delete admin_installer_path(installer)
    end
  end

  test "update saves the color" do
    installer = installers(:juan_perez)
    patch admin_installer_path(installer), params: { installer: { name: installer.name, color: "#f60404" } }
    assert_redirected_to admin_installers_path
    assert_equal "#f60404", installer.reload.color
  end

  test "index asks for confirmation before deleting an installer" do
    installer = installers(:juan_perez)
    get admin_installers_path
    assert_response :success
    assert_select "form[action=?][onsubmit=?]",
      admin_installer_path(installer), "return confirm('¿Eliminar instalador?')"
  end

  test "new and edit show the submit button in Spanish" do
    get new_admin_installer_path
    assert_response :success
    assert_select "input[value=?]", "Crear Instalador"

    get edit_admin_installer_path(installers(:juan_perez))
    assert_response :success
    assert_select "input[value=?]", "Actualizar Instalador"
  end
end
