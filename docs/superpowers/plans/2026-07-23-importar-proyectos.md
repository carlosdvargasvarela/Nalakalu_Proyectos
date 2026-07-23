# Carga masiva de proyectos vía CSV — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user pick a project type, download a CSV template whose columns are generated live from that type's `field_definitions`, fill it in a spreadsheet program, and upload it back to bulk-create `Project` records — with a partial-import report (created count + per-row errors).

**Architecture:** One new controller (`ImportsController`, 3 actions: `new`, `template`, `create`), no model/migration changes — reuses `Project`'s existing validations (`custom_fields_match_definitions`) and stage auto-creation (`build_stages_from_template`) exactly as they already work for a single manually-created project. Uses Ruby's `CSV` standard library (already available in this environment, confirmed — no Gemfile change) for both generating the template and parsing the upload.

**Tech Stack:** Ruby on Rails, Minitest, Ruby's `CSV` stdlib (`require "csv"`).

## Global Constraints

- No new gems — CSV (not `.xlsx`) by explicit design decision, using Ruby's bundled `CSV` library.
- No changes to `Project`/`ProjectStage`/`FieldDefinition` models — the importer only ever calls `Project.new(...).save`, exactly like `ProjectsController#create` already does for one project at a time.
- Reference-type fields (e.g. "Instalador") are matched by **name**, not id, in both the template and the upload — consistent with how `_field_input.html.erb` already assumes referenced models expose `:name`.
- Import is partial: one invalid row must not prevent the other valid rows in the same file from being created.

---

### Task 1: Template download + "Importar" screen entry point

**Files:**
- Modify: `config/routes.rb`
- Create: `app/controllers/imports_controller.rb`
- Create: `app/views/imports/new.html.erb`
- Modify: `app/views/layouts/_navbar.html.erb`
- Create: `test/controllers/imports_controller_test.rb`

**Interfaces:**
- Consumes: `ProjectType#field_definitions` (unchanged, `order(:position)`).
- Produces: `ImportsController#csv_template_for(project_type)` (private) — consumed internally by `#template`; Task 2 reuses the same private method for validation parity, so keep its exact name and behavior.

- [ ] **Step 1: Add the routes**

Edit `config/routes.rb`:

```ruby
Rails.application.routes.draw do
  devise_for :users
  get "up" => "rails/health#show", as: :rails_health_check
  get "manifest.json" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker.js" => "rails/pwa#service_worker", as: :pwa_service_worker

  namespace :admin do
    resources :project_types do
      resources :field_definitions, except: [:index, :show]
      resources :stage_templates, except: [:index, :show]
    end
    resources :installers
  end

  get "projects/seguimiento", to: "projects#tracker", as: :tracker_projects
  resources :projects

  resources :imports, only: [:new, :create]
  get "imports/template", to: "imports#template", as: :template_imports

  root "projects#index"
end
```

- [ ] **Step 2: Write the failing tests**

Create `test/controllers/imports_controller_test.rb`:

```ruby
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
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `bin/rails test test/controllers/imports_controller_test.rb`
Expected: FAIL — routing error (`ImportsController` doesn't exist yet).

- [ ] **Step 4: Implement `ImportsController#new`/`#template`**

Create `app/controllers/imports_controller.rb`:

```ruby
require "csv"

class ImportsController < ApplicationController
  def new
    @project_types = ProjectType.all
    @project_type = ProjectType.find_by(id: params[:project_type_id])
  end

  def template
    project_type = ProjectType.find(params[:project_type_id])
    send_data csv_template_for(project_type), filename: "plantilla-#{project_type.slug}.csv", type: "text/csv"
  end

  def create
    raise NotImplementedError
  end

  private

  def csv_template_for(project_type)
    fields = project_type.field_definitions.order(:position)
    CSV.generate do |csv|
      csv << ["Nombre"] + fields.map(&:label)
    end
  end
end
```

(`create` is a placeholder for Task 2 — this task only needs the route to exist and resolve to a real action so `resources :imports, only: [:new, :create]` doesn't error at boot; it's never called by this task's tests.)

- [ ] **Step 5: Implement `imports/new.html.erb`**

Create `app/views/imports/new.html.erb`:

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

<% if @project_type %>
  <div class="card mb-4">
    <div class="card-body">
      <p>
        1. <%= link_to "Descargar plantilla de #{@project_type.name}", template_imports_path(project_type_id: @project_type.id) %>
      </p>
      <p>2. Llená una fila por proyecto. La columna "Nombre" es obligatoria.</p>

      <%= form_with url: imports_path, method: :post, local: true, multipart: true do |form| %>
        <%= form.hidden_field :project_type_id, value: @project_type.id %>
        <div class="mb-3">
          <%= form.label :file, "Archivo lleno (CSV)", class: "form-label" %>
          <%= form.file_field :file, class: "form-control", accept: ".csv" %>
        </div>
        <%= form.submit "Importar", class: "btn btn-primary" %>
      <% end %>
    </div>
  </div>
<% end %>
```

- [ ] **Step 6: Add the nav link**

Edit `app/views/layouts/_navbar.html.erb`:

```erb
<nav class="navbar navbar-expand-lg navbar-light bg-light mb-4">
  <div class="container-fluid">
    <%= link_to "Nalakalu Proyectos", root_path, class: "navbar-brand" %>
    <div class="navbar-nav me-auto">
      <%= link_to "Proyectos", projects_path, class: "nav-link" %>
      <%= link_to "Seguimiento", tracker_projects_path, class: "nav-link" %>
      <%= link_to "Importar", new_import_path, class: "nav-link" %>
      <%= link_to "Administración", admin_project_types_path, class: "nav-link" %>
    </div>
    <div class="navbar-nav">
      <% if user_signed_in? %>
        <span class="navbar-text me-3"><%= current_user.email %></span>
        <%= button_to "Cerrar sesión", destroy_user_session_path, method: :delete, class: "btn btn-outline-secondary btn-sm" %>
      <% else %>
        <%= link_to "Iniciar sesión", new_user_session_path, class: "btn btn-outline-primary btn-sm me-2" %>
        <%= link_to "Registrarse", new_user_registration_path, class: "btn btn-primary btn-sm" %>
      <% end %>
    </div>
  </div>
</nav>
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `bin/rails test test/controllers/imports_controller_test.rb`
Expected: PASS (all tests)

- [ ] **Step 8: Add a navbar test and run the full suite**

Add to `test/controllers/navbar_test.rb`, inside the existing test class:

```ruby
  test "navbar includes a link to Importar" do
    sign_in users(:juan)
    get root_path
    assert_response :success
    assert_select "nav a[href=?]", new_import_path
  end
```

Run: `bin/rails test`
Expected: PASS

- [ ] **Step 9: Commit**

```bash
git add config/routes.rb app/controllers/imports_controller.rb app/views/imports/new.html.erb \
  app/views/layouts/_navbar.html.erb test/controllers/imports_controller_test.rb test/controllers/navbar_test.rb
git commit -m "Add CSV template download and the Importar screen entry point"
```

---

### Task 2: Upload processing, partial import, error report

**Files:**
- Modify: `app/controllers/imports_controller.rb` (`create` action + private helpers)
- Modify: `app/views/imports/new.html.erb` (results block)
- Modify: `test/controllers/imports_controller_test.rb`

**Interfaces:**
- Consumes: `ImportsController#csv_template_for` (Task 1, reused only for test fixtures in this task, not called by `create` itself), `Project.new(...).save`/`#errors` (unchanged), `FieldDefinition#reference_table`/`#key`/`#label`/`#data_type` (unchanged).
- Produces: nothing consumed by a later task — this is the last task in the plan.

- [ ] **Step 1: Write the failing tests**

Add to `test/controllers/imports_controller_test.rb`, inside the existing test class:

```ruby
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/controllers/imports_controller_test.rb`
Expected: FAIL — `create` currently raises `NotImplementedError`.

- [ ] **Step 3: Implement `create` and its private helpers**

Edit `app/controllers/imports_controller.rb` — replace:

```ruby
  def create
    raise NotImplementedError
  end
```

with:

```ruby
  def create
    @project_type = ProjectType.find(params[:project_type_id])
    @project_types = ProjectType.all
    @results = import_rows(@project_type, params[:file])
    render :new
  end
```

Add these private methods, after `csv_template_for`:

```ruby
  def import_rows(project_type, file)
    return { created: 0, errors: [{ row: 0, message: "No se subió ningún archivo" }] } if file.blank?

    fields = project_type.field_definitions.order(:position).to_a
    rows = CSV.parse(file.read, headers: true, encoding: "bom|utf-8")
    created = 0
    row_errors = []

    rows.each_with_index do |row, index|
      custom_fields = fields.each_with_object({}) do |field, hash|
        hash[field.key] = resolve_field_value(field, row[field.label])
      end
      project = Project.new(project_type: project_type, name: row["Nombre"], custom_fields: custom_fields)
      if project.save
        created += 1
      else
        row_errors << { row: index + 2, message: project.errors.full_messages.join(", ") }
      end
    end

    { created: created, errors: row_errors }
  end

  def resolve_field_value(field, raw_value)
    return raw_value if raw_value.blank? || field.data_type != "reference"

    record = field.reference_table.classify.constantize.find_by(name: raw_value.strip)
    record ? record.id : "#{raw_value} (no encontrado)"
  end
```

- [ ] **Step 4: Add the results block to the view**

Edit `app/views/imports/new.html.erb` — add at the end of the file:

```erb

<% if @results %>
  <div class="alert <%= @results[:errors].any? ? 'alert-warning' : 'alert-success' %>">
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

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bin/rails test test/controllers/imports_controller_test.rb`
Expected: PASS (all tests)

- [ ] **Step 6: Run the full suite**

Run: `bin/rails test`
Expected: PASS

- [ ] **Step 7: Manual verification**

Run: `bin/rails server`:
- Go to "Importar", pick "Instalaciones", download the template — confirm it opens correctly in a spreadsheet program (or just inspect the raw CSV) with columns "Nombre,Cliente,Instalador".
- Fill in 2-3 rows (use an existing installer's exact name for the Instalador column), save as CSV, upload it — confirm the right number of projects were created and each has stages.
- Add a row with an unknown installer name — confirm that row is reported as an error while the others still import.
- Try uploading with no file — confirm the "No se subió ningún archivo" message, no crash.

- [ ] **Step 8: Commit**

```bash
git add app/controllers/imports_controller.rb app/views/imports/new.html.erb test/controllers/imports_controller_test.rb
git commit -m "Process bulk CSV upload into Projects with a partial-import error report"
```

---

## Final verification

- [ ] Run `bin/rails test` once more — expect a clean pass.
- [ ] Confirm no new entries were added to `Gemfile`/`Gemfile.lock` (`git diff Gemfile Gemfile.lock` should be empty) — the whole point of choosing CSV was zero new dependencies.
