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
    assert_equal "Nombre,Cliente,Dirección", header
  end

  test "create builds one project per valid row, including its auto-generated stages" do
    project_type = project_types(:instalaciones)
    csv = "Nombre,Cliente,Dirección\nTorre Norte,Acme S.A.,Av. Siempre Viva 123\nTorre Sur,Beta S.A.,Calle Falsa 456\n"

    assert_difference("Project.count", 2) do
      post imports_path, params: {
        project_type_id: project_type.id,
        file: Rack::Test::UploadedFile.new(StringIO.new(csv), "text/csv", original_filename: "plantilla.csv")
      }
    end

    assert_response :success
    assert_select "body", /2 proyecto/

    torre = Project.find_by(name: "Torre Norte")
    assert_equal "Acme S.A.", torre.custom_fields["cliente"]
    assert_equal "Av. Siempre Viva 123", torre.custom_fields["direccion"]
    assert_equal 5, torre.project_stages.count
  end

  test "create skips a row with a blank Nombre and reports the error, without blocking the others" do
    project_type = project_types(:instalaciones)
    csv = "Nombre,Cliente,Dirección\n,Acme S.A.,Av. Siempre Viva 123\nTorre Sur,Beta S.A.,Calle Falsa 456\n"

    assert_difference("Project.count", 1) do
      post imports_path, params: {
        project_type_id: project_type.id,
        file: Rack::Test::UploadedFile.new(StringIO.new(csv), "text/csv", original_filename: "plantilla.csv")
      }
    end

    assert_response :success
    assert_select "body", /1 proyecto/
    assert_select "body", /Fila 2/
  end

  test "create reports an error when no file is uploaded" do
    project_type = project_types(:instalaciones)
    post imports_path, params: { project_type_id: project_type.id }
    assert_response :success
    assert_select "body", /No se subió ningún archivo/
  end

  test "preview parses a valid csv without creating any project" do
    project_type = project_types(:instalaciones)
    csv = "Nombre,Cliente,Dirección\nTorre Norte,Acme S.A.,Av. Siempre Viva 123\nTorre Sur,Beta S.A.,Calle Falsa 456\n"

    assert_no_difference("Project.count") do
      post preview_imports_path, params: {
        project_type_id: project_type.id,
        file: Rack::Test::UploadedFile.new(StringIO.new(csv), "text/csv", original_filename: "plantilla.csv")
      }
    end

    assert_response :success
    assert_select "body", /Torre Norte/
    assert_select "body", /Torre Sur/
    assert_select "input[name=?]", "valid_rows"
  end

  test "preview flags a row with a blank Nombre as an error without creating any project" do
    project_type = project_types(:instalaciones)
    csv = "Nombre,Cliente,Dirección\n,Acme S.A.,Av. Siempre Viva 123\nTorre Sur,Beta S.A.,Calle Falsa 456\n"

    assert_no_difference("Project.count") do
      post preview_imports_path, params: {
        project_type_id: project_type.id,
        file: Rack::Test::UploadedFile.new(StringIO.new(csv), "text/csv", original_filename: "plantilla.csv")
      }
    end

    assert_response :success
    assert_select "tr.table-danger td", /2/
    assert_select "tr.table-danger"
  end

  test "preview reports an error when no file is uploaded" do
    project_type = project_types(:instalaciones)
    post preview_imports_path, params: { project_type_id: project_type.id }
    assert_response :success
    assert_select "body", /No se subió ningún archivo/
  end

  test "new is blocked for a visor" do
    sign_in users(:maria)
    get new_import_path
    assert_redirected_to root_path
  end

  test "create as a gerente grants edit access on each imported project" do
    sign_in users(:carla)
    project_type = project_types(:instalaciones)
    csv = "Nombre,Cliente,Instalador\nTorre Norte,Acme S.A.,Juan Pérez\n"

    post imports_path, params: {
      project_type_id: project_type.id,
      file: Rack::Test::UploadedFile.new(StringIO.new(csv), "text/csv", original_filename: "plantilla.csv")
    }

    project = Project.find_by(name: "Torre Norte")
    assert users(:carla).can_edit_project?(project)
  end
end
