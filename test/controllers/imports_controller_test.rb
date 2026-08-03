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

  test "create builds one project per confirmed row, including its auto-generated stages" do
    project_type = project_types(:instalaciones)
    valid_rows = [
      { name: "Torre Norte", custom_fields: { "cliente" => "Acme S.A.", "direccion" => "Av. Siempre Viva 123" } },
      { name: "Torre Sur", custom_fields: { "cliente" => "Beta S.A.", "direccion" => "Calle Falsa 456" } }
    ].to_json

    assert_difference("Project.count", 2) do
      post imports_path, params: { project_type_id: project_type.id, valid_rows: valid_rows }
    end

    assert_response :success
    assert_select "body", /2 proyecto/

    torre = Project.find_by(name: "Torre Norte")
    assert_equal "Acme S.A.", torre.custom_fields["cliente"]
    assert_equal "Av. Siempre Viva 123", torre.custom_fields["direccion"]
    assert_equal 5, torre.project_stages.count
  end

  test "create with no valid_rows reports zero created" do
    project_type = project_types(:instalaciones)

    assert_no_difference("Project.count") do
      post imports_path, params: { project_type_id: project_type.id }
    end

    assert_response :success
    assert_select "body", /0 proyecto/
  end

  test "create with malformed valid_rows JSON reports zero created instead of crashing" do
    project_type = project_types(:instalaciones)

    assert_no_difference("Project.count") do
      post imports_path, params: { project_type_id: project_type.id, valid_rows: "not json{{{" }
    end

    assert_response :success
    assert_select "body", /0 proyecto/
  end

  test "create with a row missing custom_fields still creates the project" do
    project_type = project_types(:instalaciones)
    valid_rows = [{ name: "Torre Norte" }].to_json

    assert_difference("Project.count", 1) do
      post imports_path, params: { project_type_id: project_type.id, valid_rows: valid_rows }
    end

    assert_response :success
    assert_select "body", /1 proyecto/
    assert Project.exists?(name: "Torre Norte")
  end

  test "preview then create end to end: a blank Nombre row is excluded and only the valid one is created" do
    project_type = project_types(:instalaciones)
    csv = "Nombre,Cliente,Dirección\n,Acme S.A.,Av. Siempre Viva 123\nTorre Sur,Beta S.A.,Calle Falsa 456\n"

    post preview_imports_path, params: {
      project_type_id: project_type.id,
      file: Rack::Test::UploadedFile.new(StringIO.new(csv), "text/csv", original_filename: "plantilla.csv")
    }
    assert_response :success
    valid_rows_json = css_select("input[name='valid_rows']").first["value"]

    assert_difference("Project.count", 1) do
      post imports_path, params: { project_type_id: project_type.id, valid_rows: valid_rows_json }
    end

    assert_response :success
    assert_select "body", /1 proyecto/
    assert Project.exists?(name: "Torre Sur")
    assert_not Project.exists?(name: nil)
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
    valid_rows = [{ name: "Torre Norte", custom_fields: { "cliente" => "Acme S.A." } }].to_json

    post imports_path, params: { project_type_id: project_type.id, valid_rows: valid_rows }

    project = Project.find_by(name: "Torre Norte")
    assert users(:carla).can_edit_project?(project)
  end

  test "preview parses an xlsx file the same way as the equivalent csv" do
    project_type = project_types(:instalaciones)
    header = ["Nombre", "Cliente", "Dirección"]
    data_row = ["Torre Norte", "Acme S.A.", "Av. Siempre Viva 123"]

    fake_sheet = Minitest::Mock.new
    fake_sheet.expect(:row, header, [1])
    fake_sheet.expect(:last_row, 2)
    fake_sheet.expect(:row, data_row, [2])
    fake_spreadsheet = Minitest::Mock.new
    fake_spreadsheet.expect(:sheet, fake_sheet, [0])

    Roo::Spreadsheet.stub(:open, ->(path, extension:) {
      assert_equal :xlsx, extension
      fake_spreadsheet
    }) do
      assert_no_difference("Project.count") do
        post preview_imports_path, params: {
          project_type_id: project_type.id,
          file: Rack::Test::UploadedFile.new(StringIO.new("dummy"), "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", original_filename: "plantilla.xlsx")
        }
      end
    end

    assert_response :success
    assert_select "body", /Torre Norte/
    fake_sheet.verify
    fake_spreadsheet.verify
  end

  test "preview treats an unsupported file extension as no file uploaded" do
    project_type = project_types(:instalaciones)
    post preview_imports_path, params: {
      project_type_id: project_type.id,
      file: Rack::Test::UploadedFile.new(StringIO.new("hola"), "text/plain", original_filename: "notas.txt")
    }
    assert_response :success
    assert_select "body", /Formato no soportado/
  end
end
