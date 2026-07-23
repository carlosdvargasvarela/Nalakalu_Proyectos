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
end
