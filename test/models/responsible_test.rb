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

  test "destroying a responsible with assignments nullifies responsible_id but keeps the row and its snapshot" do
    project_type = project_types(:instalaciones)
    responsible_type = ResponsibleType.create!(project_type: project_type, name: "Instalador")
    responsible = Responsible.create!(name: "Ana Gómez")
    ResponsibleProjectType.create!(responsible: responsible, project_type: project_type, responsible_type: responsible_type)
    project = Project.create!(project_type: project_type, name: "Torre Norte", custom_fields: {})
    pr = ProjectResponsible.create!(project: project, responsible: responsible, responsible_type: responsible_type)

    assert_no_difference("ProjectResponsible.count") do
      responsible.destroy
    end

    pr.reload
    assert_nil pr.responsible_id
    assert_equal "Ana Gómez", pr.responsible_name
    assert_equal "#6c757d", pr.responsible_color
  end
end
