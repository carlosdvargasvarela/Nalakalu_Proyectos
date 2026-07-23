require "test_helper"

class InstallerTest < ActiveSupport::TestCase
  test "valid with name" do
    assert Installer.new(name: "Ana Gómez").valid?
  end

  test "invalid without name" do
    assert_not Installer.new.valid?
  end
end
