require "test_helper"

class Admin::AuthorizationTest < ActionDispatch::IntegrationTest
  test "admin can access admin controllers" do
    sign_in users(:juan)
    get admin_installers_path
    assert_response :success
  end

  test "gerente is redirected away from admin controllers" do
    sign_in users(:carla)
    get admin_installers_path
    assert_redirected_to root_path
    assert_equal "No tenés permiso para acceder a esa sección.", flash[:alert]
  end

  test "visor is redirected away from admin controllers" do
    sign_in users(:maria)
    get admin_installers_path
    assert_redirected_to root_path
  end
end
