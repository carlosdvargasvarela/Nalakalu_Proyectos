require "test_helper"

class ImportsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:juan) }

  test "new shows the project type selector" do
    get new_import_path
    assert_response :success
    assert_select "select[name=?]", "project_type_id"
  end

  test "new with a project_type_id shows the template download link" do
    project_type = project_types(:instalaciones)
    get new_import_path, params: { project_type_id: project_type.id }
    assert_response :success
    assert_select "a[href=?]", template_imports_path(project_type_id: project_type.id)
  end

  test "template generates a CSV with Nombre plus one column per field_definition, in position order" do
    project_type = project_types(:instalaciones)
    get template_imports_path, params: { project_type_id: project_type.id }
    assert_response :success
    assert_equal "text/csv", response.media_type
    header = response.body.lines.first.strip
    assert_equal "Nombre,Cliente,Instalador", header
  end
end
