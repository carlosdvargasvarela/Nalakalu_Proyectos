# CRUD de instaladores, archivar proyecto y edición inline de etapas — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the three gaps found while mapping the installation-tracking Excel onto the existing project/stage model: no UI to manage installers, no way to retire a project, and per-stage editing requires a separate page per row.

**Architecture:** All three pieces reuse existing Rails patterns already present in the app — the `Admin::StageTemplatesController` CRUD shape for `Installer`, `ProjectsController#update` for archiving (no new controller action), and Rails' native `accepts_nested_attributes_for` for the inline stage table (replacing the standalone `ProjectStagesController`).

**Tech Stack:** Ruby on Rails, Minitest + fixtures, Devise (auth already wired via `ApplicationController#authenticate_user!`).

## Global Constraints

- No RSpec, no new gems — Minitest is the project's test framework (per `docs/superpowers/plans/2026-07-22-project-types-y-gantt-dinamico.md`).
- Every controller test signs in first: `setup { sign_in users(:juan) }` (fixture `test/fixtures/users.yml`, `authenticate_user!` runs on all non-Devise controllers).
- Bootstrap classes only for styling (`form-control`, `btn btn-primary`, etc.) — no new CSS/JS files, no new frontend dependency.
- Deletion over addition: `ProjectStagesController`, its view, its route, and its test are removed as part of Task 3, not left dangling.

---

### Task 1: `Installer` admin CRUD

**Files:**
- Create: `app/controllers/admin/installers_controller.rb`
- Create: `app/views/admin/installers/index.html.erb`
- Create: `app/views/admin/installers/new.html.erb`
- Create: `app/views/admin/installers/edit.html.erb`
- Create: `app/views/admin/installers/_form.html.erb`
- Create: `test/controllers/admin/installers_controller_test.rb`
- Modify: `config/routes.rb` (add `resources :installers` inside the `admin` namespace)
- Modify: `app/views/admin/project_types/index.html.erb` (add nav link to installers)
- Modify: `test/controllers/admin/project_types_controller_test.rb` (assert the nav link)

**Interfaces:**
- Consumes: `Installer` model (`app/models/installer.rb`, already exists — `validates :name, presence: true`), fixture `installers(:juan_perez)` (`name: "Juan Pérez"`).
- Produces: named routes `admin_installers_path`, `new_admin_installer_path`, `edit_admin_installer_path(installer)`, `admin_installer_path(installer)` — no later task depends on these.

- [ ] **Step 1: Add the route**

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

  get "projects/dashboard", to: "projects#dashboard", as: :dashboard_projects
  resources :projects do
    resources :project_stages, only: [:edit, :update]
  end

  root "projects#index"
end
```

(The `resources :project_stages` line is removed later, in Task 3 — leave it as-is here.)

- [ ] **Step 2: Write the failing controller test**

Create `test/controllers/admin/installers_controller_test.rb`:

```ruby
require "test_helper"

class Admin::InstallersControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:juan) }

  test "index lists installers" do
    get admin_installers_path
    assert_response :success
    assert_select "body", /Juan Pérez/
  end

  test "create adds a new installer" do
    assert_difference("Installer.count", 1) do
      post admin_installers_path, params: { installer: { name: "Ana Gómez" } }
    end
    assert_redirected_to admin_installers_path
  end

  test "create with blank name re-renders form with error" do
    assert_no_difference("Installer.count") do
      post admin_installers_path, params: { installer: { name: "" } }
    end
    assert_response :unprocessable_entity
  end

  test "update changes the installer's name" do
    installer = installers(:juan_perez)
    patch admin_installer_path(installer), params: { installer: { name: "Juan P. Actualizado" } }
    assert_redirected_to admin_installers_path
    assert_equal "Juan P. Actualizado", installer.reload.name
  end

  test "destroy removes an installer" do
    installer = Installer.create!(name: "Temporal")
    assert_difference("Installer.count", -1) do
      delete admin_installer_path(installer)
    end
  end
end
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `bin/rails test test/controllers/admin/installers_controller_test.rb`
Expected: FAIL — `uninitialized constant Admin::InstallersController` (or routing error).

- [ ] **Step 4: Implement the controller**

Create `app/controllers/admin/installers_controller.rb`:

```ruby
class Admin::InstallersController < ApplicationController
  before_action :set_installer, only: [:edit, :update, :destroy]

  def index
    @installers = Installer.all
  end

  def new
    @installer = Installer.new
  end

  def create
    @installer = Installer.new(installer_params)
    if @installer.save
      redirect_to admin_installers_path
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @installer.update(installer_params)
      redirect_to admin_installers_path
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @installer.destroy
    redirect_to admin_installers_path
  end

  private

  def set_installer
    @installer = Installer.find(params[:id])
  end

  def installer_params
    params.require(:installer).permit(:name)
  end
end
```

- [ ] **Step 5: Implement the views**

Create `app/views/admin/installers/_form.html.erb`:

```erb
<%= form_with model: [:admin, installer] do |form| %>
  <% if installer.errors.any? %>
    <div class="alert alert-danger">
      <ul class="mb-0">
        <% installer.errors.full_messages.each do |message| %>
          <li><%= message %></li>
        <% end %>
      </ul>
    </div>
  <% end %>

  <div class="mb-3">
    <%= form.label :name, class: "form-label" %>
    <%= form.text_field :name, class: "form-control" %>
  </div>
  <%= form.submit class: "btn btn-primary" %>
<% end %>
```

Create `app/views/admin/installers/new.html.erb`:

```erb
<h1>Nuevo instalador</h1>
<%= render "form", installer: @installer %>
```

Create `app/views/admin/installers/edit.html.erb`:

```erb
<h1>Editar instalador</h1>
<%= render "form", installer: @installer %>
```

Create `app/views/admin/installers/index.html.erb`:

```erb
<h1>Instaladores</h1>
<%= link_to "Nuevo instalador", new_admin_installer_path, class: "btn btn-primary mb-3" %>
<ul class="list-group">
  <% @installers.each do |installer| %>
    <li class="list-group-item d-flex justify-content-between align-items-center">
      <%= installer.name %>
      <span>
        <%= link_to "Editar", edit_admin_installer_path(installer), class: "btn btn-outline-secondary btn-sm" %>
        <%= button_to "Borrar", admin_installer_path(installer), method: :delete,
              class: "btn btn-outline-danger btn-sm", form: { style: "display:inline-block" } %>
      </span>
    </li>
  <% end %>
</ul>
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `bin/rails test test/controllers/admin/installers_controller_test.rb`
Expected: PASS (5 tests)

- [ ] **Step 7: Add the nav link and its test**

Edit `app/views/admin/project_types/index.html.erb`:

```erb
<h1>Tipos de proyecto</h1>
<%= link_to "Nuevo tipo de proyecto", new_admin_project_type_path, class: "btn btn-primary mb-3" %>
<%= link_to "Instaladores", admin_installers_path, class: "btn btn-outline-secondary mb-3" %>
<ul class="list-group">
  <% @project_types.each do |project_type| %>
    <li class="list-group-item"><%= link_to project_type.name, admin_project_type_path(project_type) %></li>
  <% end %>
</ul>
```

Add to `test/controllers/admin/project_types_controller_test.rb`, inside the existing test class:

```ruby
  test "index links to installers admin" do
    get admin_project_types_path
    assert_response :success
    assert_select "a[href=?]", admin_installers_path, text: "Instaladores"
  end
```

- [ ] **Step 8: Run both test files to verify everything passes**

Run: `bin/rails test test/controllers/admin/installers_controller_test.rb test/controllers/admin/project_types_controller_test.rb`
Expected: PASS (all tests)

- [ ] **Step 9: Commit**

```bash
git add app/controllers/admin/installers_controller.rb app/views/admin/installers config/routes.rb \
  app/views/admin/project_types/index.html.erb test/controllers/admin/installers_controller_test.rb \
  test/controllers/admin/project_types_controller_test.rb
git commit -m "Add admin CRUD for installers"
```

---

### Task 2: Archive a project instead of deleting it

**Files:**
- Modify: `app/controllers/projects_controller.rb:4-6` (the `index` action)
- Modify: `app/views/projects/index.html.erb`
- Modify: `test/controllers/projects_controller_test.rb`

**Interfaces:**
- Consumes: `Project#status` (already a column, default `"active"`, already permitted in `project_params`).
- Produces: nothing new consumed by later tasks — Task 3 touches `show.html.erb`, not `index.html.erb`.

- [ ] **Step 1: Write the failing tests**

Add to `test/controllers/projects_controller_test.rb`, inside the existing test class:

```ruby
  test "index excludes archived projects" do
    Project.create!(project_type: project_types(:instalaciones), name: "Activo", custom_fields: {})
    Project.create!(
      project_type: project_types(:instalaciones), name: "Archivado", custom_fields: {}, status: "archived"
    )
    get projects_path
    assert_response :success
    assert_select "body", /Activo/
    assert_select "body", text: /Archivado/, count: 0
  end

  test "index shows an archive button for each project" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get projects_path
    assert_select "form[action=?]", project_path(project) do
      assert_select "input[value=?]", "Archivar"
    end
  end

  test "archiving a project via update sets status to archived" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    patch project_path(project), params: { project: { status: "archived" } }
    assert_redirected_to project_path(project)
    assert_equal "archived", project.reload.status
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: FAIL on "index excludes archived projects" and "index shows an archive button for each project" (the third test already passes today since `#update` already accepts `status`, but run it anyway to confirm).

- [ ] **Step 3: Filter archived projects out of the index**

Edit `app/controllers/projects_controller.rb`, the `index` method:

```ruby
  def index
    @projects = Project.includes(:project_type).where.not(status: "archived")
  end
```

- [ ] **Step 4: Add the archive button**

Edit `app/views/projects/index.html.erb`:

```erb
<h1>Proyectos</h1>
<table class="table table-striped">
  <thead>
    <tr><th>Nombre</th><th>Tipo</th><th>Estado</th><th></th></tr>
  </thead>
  <tbody>
    <% @projects.each do |project| %>
      <tr>
        <td><%= link_to project.name, project_path(project) %></td>
        <td><%= project.project_type.name %></td>
        <td><%= project.status %></td>
        <td>
          <%= link_to "Editar", edit_project_path(project), class: "btn btn-outline-secondary btn-sm" %>
          <%= button_to "Archivar", project_path(project), params: { project: { status: "archived" } },
                method: :patch, class: "btn btn-outline-danger btn-sm", form: { style: "display:inline-block" } %>
        </td>
      </tr>
    <% end %>
  </tbody>
</table>
<h2>Nuevo proyecto</h2>
<ul class="list-unstyled">
  <% ProjectType.all.each do |project_type| %>
    <li><%= link_to project_type.name, new_project_path(project_type_id: project_type.id), class: "btn btn-outline-primary btn-sm mb-1" %></li>
  <% end %>
</ul>
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: PASS (all tests, including the two `dashboard filters by status` tests already covering `"archived"` — confirm those still pass unchanged since `#dashboard` was not touched)

- [ ] **Step 6: Commit**

```bash
git add app/controllers/projects_controller.rb app/views/projects/index.html.erb test/controllers/projects_controller_test.rb
git commit -m "Add project archiving, hide archived projects from the index"
```

---

### Task 3: Inline stage-editing table on `projects#show`, retiring `ProjectStagesController`

**Files:**
- Modify: `app/models/project.rb` (add `accepts_nested_attributes_for`)
- Modify: `app/controllers/projects_controller.rb` (`project_params`)
- Modify: `app/views/projects/show.html.erb` (add the table, change Gantt `on_click`)
- Modify: `config/routes.rb` (drop nested `project_stages` resource)
- Delete: `app/controllers/project_stages_controller.rb`
- Delete: `app/views/project_stages/edit.html.erb`
- Delete: `test/controllers/project_stages_controller_test.rb`
- Modify: `test/models/project_test.rb`
- Modify: `test/controllers/projects_controller_test.rb`

**Interfaces:**
- Consumes: `Project#project_stages` (`has_many`, `app/models/project.rb:3`), `ProjectStage` columns `start_date`, `end_date`, `progress_percent` (`db/schema.rb:37-50`).
- Produces: nothing consumed by later tasks — this is the last task in the plan.

- [ ] **Step 1: Write the failing model test**

Add to `test/models/project_test.rb`, inside the existing test class:

```ruby
  test "project_stages_attributes updates existing stages without creating or destroying any" do
    project = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: {})
    stage = project.project_stages.order(:id).first

    assert_no_difference("project.project_stages.count") do
      project.update!(project_stages_attributes: { "0" => { id: stage.id, progress_percent: 75 } })
    end

    assert_equal 75, stage.reload.progress_percent
  end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test test/models/project_test.rb`
Expected: FAIL — `ArgumentError: Unknown key: :project_stages_attributes` (nested attributes writer not defined yet).

- [ ] **Step 3: Add `accepts_nested_attributes_for` to the model**

Edit `app/models/project.rb`, the top of the class:

```ruby
class Project < ApplicationRecord
  belongs_to :project_type
  has_many :project_stages, dependent: :destroy
  accepts_nested_attributes_for :project_stages, update_only: true

  validates :name, presence: true
  validate :custom_fields_match_definitions
  after_create :build_stages_from_template
```

(Everything below `after_create :build_stages_from_template` is unchanged.)

- [ ] **Step 4: Run the model test to verify it passes**

Run: `bin/rails test test/models/project_test.rb`
Expected: PASS (all tests)

- [ ] **Step 5: Write the failing controller tests**

Add to `test/controllers/projects_controller_test.rb`, inside the existing test class:

```ruby
  test "show renders an editable table row for each stage" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_path(project)
    assert_response :success
    project.project_stages.each do |stage|
      assert_select "input[type=hidden][value=?]", stage.id.to_s
    end
    assert_select "input[name$='[progress_percent]']", count: project.project_stages.count
  end

  test "updating project_stages_attributes changes stage dates and progress" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    stage = project.project_stages.order(:id).first

    patch project_path(project), params: {
      project: {
        project_stages_attributes: {
          "0" => { id: stage.id, start_date: "2026-08-01", end_date: "2026-08-10", progress_percent: 60 }
        }
      }
    }

    assert_redirected_to project_path(project)
    stage.reload
    assert_equal Date.new(2026, 8, 1), stage.start_date
    assert_equal Date.new(2026, 8, 10), stage.end_date
    assert_equal 60, stage.progress_percent
  end
```

- [ ] **Step 6: Run the tests to verify they fail**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: FAIL — the table doesn't exist yet in the view, and `project_stages_attributes` isn't permitted yet (silently dropped, so the second test fails on the `assert_equal` lines).

- [ ] **Step 7: Permit `project_stages_attributes`**

Edit `app/controllers/projects_controller.rb`, the `project_params` method:

```ruby
  def project_params
    params.require(:project).permit(
      :project_type_id, :name, :status, custom_fields: {},
      project_stages_attributes: [:id, :start_date, :end_date, :progress_percent]
    )
  end
```

- [ ] **Step 8: Add the editable table to `show.html.erb`**

Edit `app/views/projects/show.html.erb` — this file currently ends with the Gantt `<script>` block. Two changes:

1. In the `gantt_tasks` map, drop the now-unused `edit_url` key and change `on_click` to jump to the table row instead of navigating to a page that no longer exists:

```erb
<%
  # ponytail: a stage with no dates gets a one-week placeholder window starting at
  # the project's creation date, so the chart always has something to draw. This is
  # a visual approximation, not real data — real dates come from editing the stage.
  stages = @project.project_stages.includes(:stage_template).order(:id)
  gantt_tasks = stages.map do |stage|
    stage_start = stage.start_date || @project.created_at.to_date
    stage_end = stage.end_date || (stage_start + 7.days)
    {
      id: stage.id.to_s,
      name: stage.name,
      start: stage_start.to_s,
      end: stage_end.to_s,
      progress: stage.progress_percent,
      custom_class: "stage-color-#{stage.stage_template_id || 'none'}"
    }
  end
  stage_colors = stages.map { |stage| [stage.stage_template_id || "none", stage.stage_template&.color || "#6c757d"] }.uniq
%>
<style>
  <% stage_colors.each do |template_id, color| %>
    .bar-wrapper.stage-color-<%= template_id %> .bar { fill: <%= color %>; }
  <% end %>
</style>
<script type="application/json" id="gantt-tasks"><%== gantt_tasks.to_json %></script>

<script src="https://cdn.jsdelivr.net/npm/frappe-gantt@0.6.1/dist/frappe-gantt.min.js"></script>
<script>
  document.addEventListener("DOMContentLoaded", function () {
    var tasks = JSON.parse(document.getElementById("gantt-tasks").textContent);
    if (tasks.length > 0) {
      new Gantt("#gantt", tasks, {
        on_click: function (task) { window.location.hash = "stage-" + task.id; }
      });
    }
  });
</script>
```

2. Immediately after that closing `</script>` tag (end of the file), append the editable table:

```erb

<h2>Etapas</h2>
<%= form_with model: @project do |f| %>
  <table class="table table-sm table-bordered w-auto">
    <thead>
      <tr><th>Etapa</th><th>Inicio</th><th>Fin</th><th>% Avance</th></tr>
    </thead>
    <tbody>
      <%= f.fields_for :project_stages, stages do |sf| %>
        <tr id="stage-<%= sf.object.id %>">
          <td><%= sf.object.name %></td>
          <td><%= sf.hidden_field :id %><%= sf.date_field :start_date, class: "form-control form-control-sm" %></td>
          <td><%= sf.date_field :end_date, class: "form-control form-control-sm" %></td>
          <td><%= sf.number_field :progress_percent, min: 0, max: 100, class: "form-control form-control-sm" %></td>
        </tr>
      <% end %>
    </tbody>
  </table>
  <%= f.submit "Guardar cambios", class: "btn btn-primary" %>
<% end %>
```

(`stages` is the same `@project.project_stages.includes(:stage_template).order(:id)` local already computed above for the Gantt — reused here so both the chart and the table show stages in the same order.)

- [ ] **Step 9: Run the tests to verify they pass**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: PASS (all tests)

- [ ] **Step 10: Remove `ProjectStagesController` and its route**

Edit `config/routes.rb` — change:

```ruby
  resources :projects do
    resources :project_stages, only: [:edit, :update]
  end
```

to:

```ruby
  resources :projects
```

Delete the controller, view, and its test:

```bash
rm app/controllers/project_stages_controller.rb
rm app/views/project_stages/edit.html.erb
rmdir app/views/project_stages
rm test/controllers/project_stages_controller_test.rb
```

- [ ] **Step 11: Run the full test suite to confirm nothing else references the removed route**

Run: `bin/rails test`
Expected: PASS — no failures referencing `edit_project_project_stage_path` or `ProjectStagesController` anywhere in the suite (this plan's earlier tasks did not touch that helper; the only file that used it was the one just deleted).

- [ ] **Step 12: Commit**

```bash
git add app/models/project.rb app/controllers/projects_controller.rb app/views/projects/show.html.erb \
  config/routes.rb test/models/project_test.rb test/controllers/projects_controller_test.rb
git add -u app/controllers/project_stages_controller.rb app/views/project_stages/edit.html.erb \
  test/controllers/project_stages_controller_test.rb
git commit -m "Replace per-stage edit page with an inline editable table on the project page"
```

---

## Final verification

- [ ] Run the entire suite once more after all three tasks: `bin/rails test`
- [ ] Expected: all tests pass, zero references remain to `project_stages#edit`/`#update` routes or `ProjectStagesController` anywhere in `app/` or `test/` (`grep -r "project_project_stage" app test` should return nothing).
