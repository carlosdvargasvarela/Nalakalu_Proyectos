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

  test "create builds one project per valid row, including its auto-generated stages" do
    project_type = project_types(:instalaciones)
    csv = "Nombre,Cliente,Instalador\nTorre Norte,Acme S.A.,Juan Pérez\nTorre Sur,Beta S.A.,Juan Pérez\n"

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
    assert_equal installers(:juan_perez).id.to_s, torre.custom_fields["instalador"].to_s
    assert_equal 5, torre.project_stages.count
  end

  test "create skips a row with a blank Nombre and reports the error, without blocking the others" do
    project_type = project_types(:instalaciones)
    csv = "Nombre,Cliente,Instalador\n,Acme S.A.,Juan Pérez\nTorre Sur,Beta S.A.,Juan Pérez\n"

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

  test "create reports an error when a reference field's name doesn't match any record" do
    project_type = project_types(:instalaciones)
    csv = "Nombre,Cliente,Instalador\nTorre Norte,Acme S.A.,No Existe\n"

    assert_no_difference("Project.count") do
      post imports_path, params: {
        project_type_id: project_type.id,
        file: Rack::Test::UploadedFile.new(StringIO.new(csv), "text/csv", original_filename: "plantilla.csv")
      }
    end

    assert_response :success
    assert_select "body", /Fila 2/
    assert_select "body", /Instalador/
  end

  test "create reports an error when no file is uploaded" do
    project_type = project_types(:instalaciones)
    post imports_path, params: { project_type_id: project_type.id }
    assert_response :success
    assert_select "body", /No se subió ningún archivo/
  end
end
