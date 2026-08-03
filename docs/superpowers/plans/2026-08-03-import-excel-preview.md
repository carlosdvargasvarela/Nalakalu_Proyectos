# Carga masiva: soporte Excel + vista previa de errores Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the bulk project import accept `.xlsx`/`.xls` files in addition to `.csv`, and show a preview of parsed rows (with per-row errors) before anything is saved, requiring an explicit confirmation step to actually create the projects.

**Architecture:** All logic stays in `ImportsController` (no new services/jobs — matches the existing import's pattern). A new `preview` action parses the uploaded file (CSV via stdlib `CSV`, xlsx/xls via the `roo` gem) into rows, validates each row against an in-memory (unsaved) `Project`, and renders a preview table. The rows that passed validation travel to the `create` action as a JSON string in a hidden field — `create` no longer reads a file, it deserializes that JSON and saves.

**Tech Stack:** Ruby on Rails, Minitest (fixtures, `ActionDispatch::IntegrationTest`), stdlib `CSV`, new gem `roo` (xlsx/xls reading).

## Global Constraints

- No new services/background jobs — logic stays in `ImportsController`, same as the existing CSV-only import.
- No new gem beyond `roo` for file reading (see `docs/superpowers/specs/2026-08-03-import-excel-preview-design.md`).
- Preview step must not create any `Project`/`ProjectAccess` records — only `create` (the confirmation step) writes to the DB.
- Row numbers reported to the user always count the header as row 1 (data starts at row 2), for CSV and Excel alike.
- `reference`-type fields keep being resolved by name via `resolve_field_value` (unchanged).

---

### Task 1: Routes + CSV preview action + preview view

**Files:**
- Modify: `Gemfile:62-63` (add `roo` gem after the `csv` gem)
- Modify: `config/routes.rb:32` (`resources :imports, only: [:new, :create]` → add a `preview` collection route)
- Modify: `app/controllers/imports_controller.rb` (add `preview` action, `build_preview`, refactor file-parsing into `parse_rows`; CSV branch only for this task — xlsx/xls comes in Task 2)
- Modify: `app/views/imports/new.html.erb` (add the preview table + confirm form block; change the upload form's action/accept)
- Test: `test/controllers/imports_controller_test.rb` (new tests for `preview`)

**Interfaces:**
- Produces: `ImportsController#preview` (route: `POST /imports/preview`, name `preview_imports_path`)
- Produces: `ImportsController#build_preview(project_type, file) -> { rows: [{ row:, name:, custom_fields:, error: }], valid_rows_json: String }`
- Produces: `ImportsController#parse_rows(file, fields) -> Array<[name, custom_fields_hash]>` (CSV-only for now; called by `build_preview`)
- Consumes: `ImportsController#resolve_field_value` (already exists, unchanged)

- [ ] **Step 1: Add the `roo` gem**

In `Gemfile`, right after the existing `csv` gem block (around line 63):

```ruby
# Ruby 3.4+ removed csv from default gems; needed by ImportsController for template generation.
gem "csv"

# Reads .xlsx/.xls uploads for carga masiva (CSV keeps using the stdlib csv gem above).
gem "roo"
```

Run: `bundle install`
Expected: `Gemfile.lock` gains a `roo` entry (and its dependencies, e.g. `rubyzip`), command exits 0.

- [ ] **Step 2: Add the `preview` route**

In `config/routes.rb:32`, replace:

```ruby
resources :imports, only: [:new, :create]
```

with:

```ruby
resources :imports, only: [:new, :create] do
  collection { post :preview }
end
```

(The existing `get "imports/template", to: "imports#template", as: :template_imports` line stays as-is.)

- [ ] **Step 3: Write the failing tests for `preview` (CSV)**

Add to `test/controllers/imports_controller_test.rb` (inside the `ImportsControllerTest` class, near the other `create` tests):

```ruby
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
  assert_select "body", /Fila 2/
  assert_select "tr.table-danger"
end

test "preview reports an error when no file is uploaded" do
  project_type = project_types(:instalaciones)
  post preview_imports_path, params: { project_type_id: project_type.id }
  assert_response :success
  assert_select "body", /No se subió ningún archivo/
end
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `bin/rails test test/controllers/imports_controller_test.rb -n "/preview/"`
Expected: FAIL — `preview_imports_path` undefined / routing error, since the route and action don't exist yet.

- [ ] **Step 5: Implement the route, `preview` action, `build_preview`, and `parse_rows` (CSV branch)**

In `app/controllers/imports_controller.rb`, add `require "roo"` after `require "csv"` at the top, add the `preview` action, and replace the body of `import_rows`/add the new private methods. Full resulting file:

```ruby
require "csv"
require "roo"

class ImportsController < ApplicationController
  before_action :require_admin_or_gerente!

  def new
    @project_types = ProjectType.all
    @project_type = ProjectType.find_by(id: params[:project_type_id])
  end

  def template
    project_type = ProjectType.find(params[:project_type_id])
    send_data csv_template_for(project_type), filename: "plantilla-#{project_type.slug}.csv", type: "text/csv"
  end

  def preview
    @project_type = ProjectType.find(params[:project_type_id])
    @project_types = ProjectType.all
    @preview = build_preview(@project_type, params[:file])
    render :new
  end

  def create
    @project_type = ProjectType.find(params[:project_type_id])
    @project_types = ProjectType.all
    @results = { created: 0, errors: [] }
    render :new
  end

  private

  def csv_template_for(project_type)
    fields = project_type.field_definitions.order(:position)
    CSV.generate do |csv|
      csv << ["Nombre"] + fields.map(&:label)
    end
  end

  def build_preview(project_type, file)
    return { rows: [{ row: 0, name: nil, custom_fields: {}, error: "No se subió ningún archivo" }], valid_rows_json: "[]" } if file.blank?

    fields = project_type.field_definitions.order(:position).to_a
    parsed_rows = parse_rows(file, fields)
    rows = []
    valid_rows = []

    parsed_rows.each_with_index do |(name, custom_fields), index|
      project = Project.new(project_type: project_type, name: name, custom_fields: custom_fields)
      if project.valid?
        rows << { row: index + 2, name: name, custom_fields: custom_fields, error: nil }
        valid_rows << { name: name, custom_fields: custom_fields }
      else
        rows << { row: index + 2, name: name, custom_fields: custom_fields, error: project.errors.full_messages.join(", ") }
      end
    end

    { rows: rows, valid_rows_json: valid_rows.to_json }
  end

  def parse_rows(file, fields)
    extension = File.extname(file.original_filename).downcase

    case extension
    when ".csv"
      CSV.parse(file.read.force_encoding("UTF-8").sub("﻿", ""), headers: true).map do |row|
        [row["Nombre"], fields.each_with_object({}) { |f, h| h[f.key] = resolve_field_value(f, row[f.label]) }]
      end
    else
      raise NotImplementedError, "xlsx/xls support added in a later task"
    end
  end

  def resolve_field_value(field, raw_value)
    return raw_value if raw_value.blank? || field.data_type != "reference"

    record = field.reference_table.classify.constantize.find_by(name: raw_value.strip)
    record ? record.id : "#{raw_value} (no encontrado)"
  end
end
```

(`create` is a stub for this task — Task 3 replaces its body with the real confirm logic. This keeps the task buildable/testable in isolation.)

- [ ] **Step 6: Update the view with the preview block**

Replace `app/views/imports/new.html.erb` entirely with:

```erb
<h1>Importar proyectos</h1>

<%= form_with url: new_import_path, method: :get, local: true, class: "row g-2 mb-4" do |form| %>
  <div class="col-auto">
    <%= form.label :project_type_id, "Tipo de proyecto", class: "form-label" %>
    <%= form.select :project_type_id, @project_types.collect { |pt| [pt.name, pt.id] },
          { selected: @project_type&.id, include_blank: "Elegí un tipo" }, class: "form-select" %>
  </div>
  <div class="col-auto align-self-end">
    <%= form.submit "Ver plantilla", class: "btn btn-outline-secondary" %>
  </div>
<% end %>

<% if @project_type && !@preview && !@results %>
  <div class="card mb-4">
    <div class="card-body">
      <p>
        1. <%= link_to "Descargar plantilla de #{@project_type.name}", template_imports_path(project_type_id: @project_type.id) %>
      </p>
      <p>2. Llená una fila por proyecto. La columna "Nombre" es obligatoria.</p>

      <%= form_with url: preview_imports_path, method: :post, local: true, multipart: true do |form| %>
        <%= form.hidden_field :project_type_id, value: @project_type.id %>
        <div class="mb-3">
          <%= form.label :file, "Archivo lleno (CSV o Excel)", class: "form-label" %>
          <%= form.file_field :file, class: "form-control", accept: ".csv,.xlsx,.xls" %>
        </div>
        <%= form.submit "Ver vista previa", class: "btn btn-primary" %>
      <% end %>
    </div>
  </div>
<% end %>

<% if @preview %>
  <div class="card mb-4">
    <div class="card-body">
      <h2 class="h5">Vista previa</h2>
      <table class="table table-sm">
        <thead>
          <tr>
            <th>Fila</th>
            <th>Nombre</th>
            <th>Error</th>
          </tr>
        </thead>
        <tbody>
          <% @preview[:rows].each do |row| %>
            <tr class="<%= "table-danger" if row[:error] %>">
              <td><%= row[:row] %></td>
              <td><%= row[:name] %></td>
              <td><%= row[:error] %></td>
            </tr>
          <% end %>
        </tbody>
      </table>

      <% if @preview[:rows].any? { |r| r[:error].nil? } %>
        <%= form_with url: imports_path, method: :post, local: true do |form| %>
          <%= form.hidden_field :project_type_id, value: @project_type.id %>
          <%= form.hidden_field :valid_rows, value: @preview[:valid_rows_json] %>
          <%= form.submit "Confirmar importación", class: "btn btn-primary" %>
        <% end %>
      <% else %>
        <p class="text-muted">Ninguna fila es válida — corregí el archivo y volvé a subirlo.</p>
      <% end %>

      <%= link_to "Subir otro archivo", new_import_path(project_type_id: @project_type.id), class: "btn btn-outline-secondary mt-2" %>
    </div>
  </div>
<% end %>

<% if @results %>
  <div class="alert <%= @results[:errors].any? ? "alert-warning" : "alert-success" %>">
    <%= @results[:created] %> proyecto(s) creado(s).
    <% if @results[:errors].any? %>
      <p class="mb-0 mt-2">Filas con error:</p>
      <ul class="mb-0">
        <% @results[:errors].each do |error| %>
          <li>Fila <%= error[:row] %>: <%= error[:message] %></li>
        <% end %>
      </ul>
    <% end %>
  </div>
<% end %>
```

- [ ] **Step 7: Run the new tests to verify they pass**

Run: `bin/rails test test/controllers/imports_controller_test.rb -n "/preview/"`
Expected: PASS (3 tests, 0 failures).

- [ ] **Step 8: Run the full import test file to check for regressions**

Run: `bin/rails test test/controllers/imports_controller_test.rb`
Expected: the pre-existing `create` tests now FAIL (since `create` is stubbed in this task) — that's expected and gets fixed in Task 3. Confirm only those `create`-related tests fail, nothing else.

- [ ] **Step 9: Commit**

```bash
git add Gemfile Gemfile.lock config/routes.rb app/controllers/imports_controller.rb app/views/imports/new.html.erb test/controllers/imports_controller_test.rb
git commit -m "Add CSV preview step to bulk import"
```

---

### Task 2: xlsx/xls parsing via `roo`

**Files:**
- Modify: `app/controllers/imports_controller.rb` (`parse_rows` — replace the `else` branch's `NotImplementedError` with real xlsx/xls handling; add an "unsupported extension" branch)
- Test: `test/controllers/imports_controller_test.rb`

**Interfaces:**
- Consumes: `ImportsController#build_preview` (from Task 1, unchanged)
- Produces: `ImportsController#parse_rows` now handles `.csv`, `.xlsx`, `.xls`, and anything else (treated as "no file")

- [ ] **Step 1: Write the failing tests**

Add to `test/controllers/imports_controller_test.rb`:

```ruby
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

  Roo::Spreadsheet.stub(:open, fake_spreadsheet) do
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/controllers/imports_controller_test.rb -n "/xlsx|unsupported/"`
Expected: FAIL — the xlsx test raises `NotImplementedError`; the unsupported-extension test doesn't show the expected message yet.

- [ ] **Step 3: Implement xlsx/xls parsing**

In `app/controllers/imports_controller.rb`, replace `parse_rows`:

```ruby
def parse_rows(file, fields)
  extension = File.extname(file.original_filename).downcase

  case extension
  when ".csv"
    CSV.parse(file.read.force_encoding("UTF-8").sub("﻿", ""), headers: true).map do |row|
      [row["Nombre"], fields.each_with_object({}) { |f, h| h[f.key] = resolve_field_value(f, row[f.label]) }]
    end
  when ".xlsx", ".xls"
    sheet = Roo::Spreadsheet.open(file.path, extension: extension.delete(".").to_sym).sheet(0)
    header = sheet.row(1)
    (2..sheet.last_row).map do |i|
      row = header.zip(sheet.row(i)).to_h
      [row["Nombre"], fields.each_with_object({}) { |f, h| h[f.key] = resolve_field_value(f, row[f.label]) }]
    end
  else
    raise ArgumentError, "unsupported extension"
  end
end
```

And in `build_preview`, catch the unsupported-extension case (still in `app/controllers/imports_controller.rb`):

```ruby
def build_preview(project_type, file)
  return { rows: [{ row: 0, name: nil, custom_fields: {}, error: "No se subió ningún archivo" }], valid_rows_json: "[]" } if file.blank?

  fields = project_type.field_definitions.order(:position).to_a
  parsed_rows = begin
    parse_rows(file, fields)
  rescue ArgumentError
    return { rows: [{ row: 0, name: nil, custom_fields: {}, error: "Formato no soportado, subí un .csv, .xlsx o .xls" }], valid_rows_json: "[]" }
  end
  rows = []
  valid_rows = []

  parsed_rows.each_with_index do |(name, custom_fields), index|
    project = Project.new(project_type: project_type, name: name, custom_fields: custom_fields)
    if project.valid?
      rows << { row: index + 2, name: name, custom_fields: custom_fields, error: nil }
      valid_rows << { name: name, custom_fields: custom_fields }
    else
      rows << { row: index + 2, name: name, custom_fields: custom_fields, error: project.errors.full_messages.join(", ") }
    end
  end

  { rows: rows, valid_rows_json: valid_rows.to_json }
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/controllers/imports_controller_test.rb -n "/xlsx|unsupported/"`
Expected: PASS (2 tests, 0 failures).

- [ ] **Step 5: Commit**

```bash
git add app/controllers/imports_controller.rb test/controllers/imports_controller_test.rb
git commit -m "Support xlsx/xls uploads in bulk import preview via roo"
```

---

### Task 3: Confirmation step (`create` consumes `valid_rows`)

**Files:**
- Modify: `app/controllers/imports_controller.rb` (`create` action — replace the stub from Task 1 with real logic; add `commit_rows`)
- Modify: `test/controllers/imports_controller_test.rb` (update the pre-existing `create` tests to go through the new two-step flow instead of posting a file directly)

**Interfaces:**
- Consumes: `params[:valid_rows]` — JSON string produced by `@preview[:valid_rows_json]` from Task 1/2, an array of `{ "name" => ..., "custom_fields" => {...} }`
- Produces: `ImportsController#commit_rows(project_type, valid_rows) -> { created:, errors: [{ row:, message: }] }` (same shape `@results` already had)

- [ ] **Step 1: Update the pre-existing `create` tests to the new two-step flow**

In `test/controllers/imports_controller_test.rb`, replace the three tests that post a file directly to `imports_path` for `create` with the confirm-step equivalents. Replace:

```ruby
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
```

with:

```ruby
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

test "preview then create end to end: a blank Nombre row is excluded and only the valid one is created" do
  project_type = project_types(:instalaciones)
  csv = "Nombre,Cliente,Dirección\n,Acme S.A.,Av. Siempre Viva 123\nTorre Sur,Beta S.A.,Calle Falsa 456\n"

  post preview_imports_path, params: {
    project_type_id: project_type.id,
    file: Rack::Test::UploadedFile.new(StringIO.new(csv), "text/csv", original_filename: "plantilla.csv")
  }
  assert_response :success
  valid_rows_json = css_select("input[name=?]", "valid_rows").first["value"]

  assert_difference("Project.count", 1) do
    post imports_path, params: { project_type_id: project_type.id, valid_rows: valid_rows_json }
  end

  assert_response :success
  assert_select "body", /1 proyecto/
  assert Project.exists?(name: "Torre Sur")
  assert_not Project.exists?(name: nil)
end
```

Also replace the gerente test (currently posts a file to `imports_path`):

```ruby
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
```

with:

```ruby
test "create as a gerente grants edit access on each imported project" do
  sign_in users(:carla)
  project_type = project_types(:instalaciones)
  valid_rows = [{ name: "Torre Norte", custom_fields: { "cliente" => "Acme S.A." } }].to_json

  post imports_path, params: { project_type_id: project_type.id, valid_rows: valid_rows }

  project = Project.find_by(name: "Torre Norte")
  assert users(:carla).can_edit_project?(project)
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/controllers/imports_controller_test.rb`
Expected: FAIL — `create` is still the Task 1 stub, so `Project.count` doesn't change and "0 proyecto(s) creado(s)" shows even for the 2-row test.

- [ ] **Step 3: Implement the real `create` action and `commit_rows`**

In `app/controllers/imports_controller.rb`, replace the `create` action:

```ruby
def create
  @project_type = ProjectType.find(params[:project_type_id])
  @project_types = ProjectType.all
  valid_rows = JSON.parse(params[:valid_rows] || "[]")
  @results = commit_rows(@project_type, valid_rows)
  render :new
end
```

and add `commit_rows` as a private method (next to `build_preview`):

```ruby
def commit_rows(project_type, valid_rows)
  created = 0
  row_errors = []

  valid_rows.each_with_index do |row, index|
    project = Project.new(project_type: project_type, name: row["name"], custom_fields: row["custom_fields"])
    if project.save
      ProjectAccess.create!(user: current_user, project: project, can_edit: true) if current_user.gerente?
      created += 1
    else
      row_errors << { row: index + 2, message: project.errors.full_messages.join(", ") }
    end
  end

  { created: created, errors: row_errors }
end
```

- [ ] **Step 4: Run the full test file to verify everything passes**

Run: `bin/rails test test/controllers/imports_controller_test.rb`
Expected: PASS, all tests green (0 failures, 0 errors).

- [ ] **Step 5: Commit**

```bash
git add app/controllers/imports_controller.rb test/controllers/imports_controller_test.rb
git commit -m "Confirm bulk import from previewed rows instead of re-reading the file"
```

---

## Final Verification

- [ ] Run the full suite once more to confirm no regressions elsewhere: `bin/rails test`
