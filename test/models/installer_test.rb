require "test_helper"

class InstallerTest < ActiveSupport::TestCase
  test "valid with name" do
    assert Installer.new(name: "Ana Gómez").valid?
  end

  test "invalid without name" do
    assert_not Installer.new.valid?
  end

  test "valid with default color" do
    installer = Installer.new(name: "Ana Gómez")
    assert installer.valid?
    assert_equal "#6c757d", installer.color
  end

  test "invalid with a malformed color" do
    installer = Installer.new(name: "Ana Gómez", color: "blue")
    assert_not installer.valid?
  end
end
