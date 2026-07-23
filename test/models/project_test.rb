require "test_helper"

class ProjectTest < ActiveSupport::TestCase
  setup do
    @project_type = project_types(:instalaciones)
  end

  test "valid with correct custom_fields types" do
    project = Project.new(
      project_type: @project_type,
      name: "Instalación Torre Norte",
      custom_fields: { "cliente" => "Acme S.A.", "instalador" => installers(:juan_perez).id }
    )
    assert project.valid?, project.errors.full_messages.to_s
  end

  test "invalid when reference field points to a nonexistent installer" do
    project = Project.new(
      project_type: @project_type,
      name: "Instalación Torre Norte",
      custom_fields: { "cliente" => "Acme S.A.", "instalador" => 999_999 }
    )
    assert_not project.valid?
    assert_includes project.errors[:custom_fields].join, "Instalador"
  end

  test "invalid when text field is not a string" do
    project = Project.new(
      project_type: @project_type,
      name: "Instalación Torre Norte",
      custom_fields: { "cliente" => 12345 }
    )
    assert_not project.valid?
  end

  test "valid when a field is simply absent (not required)" do
    project = Project.new(
      project_type: @project_type,
      name: "Instalación Torre Norte",
      custom_fields: {}
    )
    assert project.valid?
  end
end
