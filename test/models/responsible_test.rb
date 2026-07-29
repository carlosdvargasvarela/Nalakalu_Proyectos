require "test_helper"

class ResponsibleTest < ActiveSupport::TestCase
  test "valid with name" do
    assert Responsible.new(name: "Ana Gómez").valid?
  end

  test "invalid without name" do
    assert_not Responsible.new.valid?
  end

  test "valid with default color" do
    responsible = Responsible.new(name: "Ana Gómez")
    assert responsible.valid?
    assert_equal "#6c757d", responsible.color
  end

  test "invalid with a malformed color" do
    assert_not Responsible.new(name: "Ana Gómez", color: "blue").valid?
  end

  test "valid without a linked user" do
    assert Responsible.new(name: "Ana Gómez", user: nil).valid?
  end

  test "invalid when the linked user is already linked to another responsible" do
    Responsible.create!(name: "Ana Gómez", user: users(:maria))
    dup = Responsible.new(name: "Otra Persona", user: users(:maria))
    assert_not dup.valid?
  end
end
