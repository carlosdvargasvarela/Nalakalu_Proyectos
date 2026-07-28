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
end
