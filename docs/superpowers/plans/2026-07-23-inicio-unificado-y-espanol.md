# Pantalla de inicio unificada, Gantt de solo lectura y app en español — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop the user from bouncing between "Proyectos" and "Gerencia" for the same information, stop the Gantt charts from looking editable when they aren't, add an installer filter, and close the remaining English-language gap (Devise's default views and validation messages).

**Architecture:** One merged `ProjectsController#index` replaces the two existing screens. The Gantt read-only behavior is a client-side snap-back (the library has no native readonly mode — confirmed by reading the actual bundle). Devise localization is direct Spanish text in generated views (no `t()` layer — this app targets one language only) plus locale files for the messages Devise/ActiveModel generate through `I18n.t` at the controller/model layer.

**Tech Stack:** Ruby on Rails, Minitest + fixtures, Devise 5.0.4, frappe-gantt 0.6.1 (CDN), Bootstrap 5.3.3 (CDN).

## Global Constraints

- No new gems — the Spanish validation-message coverage is hand-written for the messages this app actually triggers, not a full `rails-i18n`/`devise-i18n` install (see Task 3).
- No RSpec — Minitest is the project's test framework. Every controller test signs in first: `setup { sign_in users(:juan) }`.
- Bootstrap classes only for styling, no new CSS/JS dependency.
- `frappe-gantt` has no `readonly` option (verified by downloading and reading `https://cdn.jsdelivr.net/npm/frappe-gantt@0.6.1/dist/frappe-gantt.min.js` directly — its `trigger_event` method reads `options["on_" + event]`, and the only mutation events it fires are `date_change` and `progress_change`). The read-only behavior in Tasks 1 and uses `gantt.refresh(tasks)` inside those two callbacks — do not attempt a `readonly:` option, it does not exist in this version.
- Devise's bundled views (`devise-5.0.4`) hardcode English text directly (not via `t()`) except for flash/mailer strings and attribute labels, which route through `I18n.t`. Task 2 hardcodes Spanish text directly in the copied views; Task 3 supplies the `I18n.t`-driven pieces.

---

### Task 1: Unified home screen (merge `index` + `dashboard`, installer filter, read-only Gantt)

**Files:**
- Modify: `app/controllers/projects_controller.rb` (replace `index`, delete `dashboard`, add `filter_by_installer`)
- Modify: `app/views/projects/index.html.erb` (replace entirely — absorbs `dashboard.html.erb`'s filters/Gantt)
- Delete: `app/views/projects/dashboard.html.erb`
- Modify: `app/views/projects/show.html.erb` (Gantt options only — add `language`/read-only snap-back)
- Modify: `config/routes.rb` (remove the `dashboard_projects` route)
- Modify: `app/views/layouts/_navbar.html.erb` (remove the "Gerencia" link)
- Modify: `test/controllers/projects_controller_test.rb` (rewrite — merge/rename dashboard tests into index, add installer-filter tests)
- Modify: `test/controllers/navbar_test.rb` (remove the dashboard-link test)

**Interfaces:**
- Consumes: `Project#gantt_window`, `Project#current_stage` (`app/models/project.rb`, unchanged), `FieldDefinition` (`reference_table`, `key` columns, unchanged), `Installer` (unchanged).
- Produces: nothing consumed by later tasks — Tasks 2 and 3 touch unrelated files (Devise views, locale files).

- [ ] **Step 1: Write the failing controller tests**

Replace the full contents of `test/controllers/projects_controller_test.rb` with:

```ruby
require "test_helper"

class ProjectsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:juan) }

  test "index lists projects" do
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get projects_path
    assert_response :success
    assert_select "body", /Torre Norte/
  end

  test "new renders one input per field_definition of the selected type" do
    get new_project_path(project_type_id: project_types(:instalaciones).id)
    assert_response :success
    assert_select "input[name=?]", "project[custom_fields][cliente]"
    assert_select "select[name=?]", "project[custom_fields][instalador]"
  end

  test "create with valid custom_fields builds the project and its stages" do
    assert_difference("Project.count", 1) do
      post projects_path, params: {
        project: {
          project_type_id: project_types(:instalaciones).id,
          name: "Torre Sur",
          custom_fields: { cliente: "Acme S.A.", instalador: installers(:juan_perez).id }
        }
      }
    end
    project = Project.order(:id).last
    assert_redirected_to project_path(project)
    assert_equal 5, project.project_stages.count
  end

  test "create with invalid custom_fields re-renders form with error" do
    assert_no_difference("Project.count") do
      post projects_path, params: {
        project: {
          project_type_id: project_types(:instalaciones).id,
          name: "Torre Sur",
          custom_fields: { cliente: "Acme S.A.", instalador: 999_999 }
        }
      }
    end
    assert_response :unprocessable_entity
  end

  test "show displays custom fields and the stage table" do
    project = Project.create!(
      project_type: project_types(:instalaciones), name: "Torre Norte",
      custom_fields: { cliente: "Acme S.A." }
    )
    get project_path(project)
    assert_response :success
    assert_select "body", /Acme S.A./
    assert_select "body", /Producción/
  end

  test "show renders a Gantt column for each show_in_gantt field, with the project's value shown once" do
    project = Project.create!(
      project_type: project_types(:instalaciones), name: "Torre Norte",
      custom_fields: { cliente: "Acme S.A." }
    )
    get project_path(project)
    assert_response :success
    assert_select "table th", text: "Cliente"
    assert_select "table td", text: "Acme S.A.", count: 1
  end

  test "show renders the Gantt chart container with one task per stage" do
    project = Project.create!(
      project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {}
    )
    get project_path(project)
    assert_response :success
    assert_select "#gantt"
    assert_select "script#gantt-tasks", text: /#{project.project_stages.first.name}/
  end

  test "show configures the Gantt in Spanish with a read-only snap-back on drag" do
    project = Project.create!(
      project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {}
    )
    get project_path(project)
    assert_response :success
    assert_match(/language:\s*"es"/, response.body)
    assert_match(/on_date_change:\s*function\s*\(\)\s*\{\s*gantt\.refresh\(tasks\);\s*\}/, response.body)
    assert_match(/on_progress_change:\s*function\s*\(\)\s*\{\s*gantt\.refresh\(tasks\);\s*\}/, response.body)
  end

  test "index shows an edit link for each project" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get projects_path
    assert_select "a[href=?]", edit_project_path(project), text: "Editar"
  end

  test "show has an edit link" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_path(project)
    assert_select "a[href=?]", edit_project_path(project), text: "Editar"
  end

  test "show colors each stage's Gantt bar by its stage_template's color" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    stage_templates(:produccion).update!(color: "#ff0000")

    get project_path(project)
    assert_response :success
    assert_match(
      /\.bar-wrapper\.stage-color-#{stage_templates(:produccion).id}\s*\.bar\s*\{\s*fill:\s*#ff0000;?\s*\}/,
      response.body
    )
  end

  test "index shows one Gantt task per project by default" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get projects_path
    assert_response :success
    assert_select "script#gantt-tasks", text: /#{project.name}/
  end

  test "index configures the Gantt in Spanish with a read-only snap-back on drag" do
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get projects_path
    assert_response :success
    assert_match(/language:\s*"es"/, response.body)
    assert_match(/on_date_change:\s*function\s*\(\)\s*\{\s*gantt\.refresh\(tasks\);\s*\}/, response.body)
  end

  test "index filters by project_type" do
    other_type = ProjectType.create!(name: "Mantenimiento", slug: "mantenimiento")
    torre = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    otro = Project.create!(project_type: other_type, name: "Proyecto Otro Tipo", custom_fields: {})

    get projects_path, params: { project_type_id: other_type.id }
    assert_response :success
    assert_match(/#{otro.name}/, response.body)
    assert_no_match(/#{torre.name}/, response.body)
  end

  test "index filters by status" do
    torre = Project.create!(
      project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {}, status: "active"
    )
    vieja = Project.create!(
      project_type: project_types(:instalaciones), name: "Torre Vieja", custom_fields: {}, status: "archived"
    )

    get projects_path, params: { status: "archived" }
    assert_response :success
    assert_match(/#{vieja.name}/, response.body)
    assert_no_match(/#{torre.name}/, response.body)
  end

  test "index filters by installer" do
    otro_instalador = Installer.create!(name: "Otro Instalador")
    con_juan = Project.create!(
      project_type: project_types(:instalaciones), name: "Con Juan", custom_fields: { instalador: installers(:juan_perez).id }
    )
    con_otro = Project.create!(
      project_type: project_types(:instalaciones), name: "Con Otro", custom_fields: { instalador: otro_instalador.id }
    )

    get projects_path, params: { installer_id: installers(:juan_perez).id }
    assert_response :success
    assert_match(/#{con_juan.name}/, response.body)
    assert_no_match(/#{con_otro.name}/, response.body)
  end

  test "index shows a message and no Gantt when no projects match the filters" do
    get projects_path, params: { status: "nonexistent-status" }
    assert_response :success
    assert_select "body", /No hay proyectos con estos filtros/
    assert_select "#gantt", count: 0
  end

  test "index excludes archived projects by default" do
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
end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: FAIL — `dashboard_projects_path`/`dashboard` route no longer referenced (good, already removed from this file), but the new "index filters by..." / "index shows one Gantt task..." / "installer" / "Spanish" tests fail because `#index` doesn't yet compute `@installers`, doesn't yet render a Gantt, and the Gantt options don't yet include `language`/`on_date_change`.

- [ ] **Step 3: Rewrite the controller**

Replace `app/controllers/projects_controller.rb` in full:

```ruby
class ProjectsController < ApplicationController
  before_action :set_project, only: [:show, :edit, :update]

  def index
    @project_types = ProjectType.all
    @statuses = Project.distinct.pluck(:status).compact
    @installers = Installer.all
    @projects = Project.includes(:project_type, project_stages: :stage_template)
    @projects = params[:status].present? ? @projects.where(status: params[:status]) : @projects.where.not(status: "archived")
    @projects = @projects.where(project_type_id: params[:project_type_id]) if params[:project_type_id].present?
    @projects = filter_by_installer(@projects, params[:installer_id]) if params[:installer_id].present?
  end

  def show
  end

  def new
    @project_type = ProjectType.find(params[:project_type_id]) if params[:project_type_id]
    @project = Project.new(project_type: @project_type)
  end

  def create
    @project = Project.new(project_params)
    @project_type = @project.project_type
    if @project.save
      redirect_to project_path(@project)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @project_type = @project.project_type
  end

  def update
    @project_type = @project.project_type
    if @project.update(project_params)
      redirect_to project_path(@project)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_project
    @project = Project.find(params[:id])
  end

  def project_params
    params.require(:project).permit(
      :project_type_id, :name, :status, custom_fields: {},
      project_stages_attributes: [:id, :start_date, :end_date, :progress_percent]
    )
  end

  def filter_by_installer(scope, installer_id)
    keys = FieldDefinition.where(reference_table: "installers").distinct.pluck(:key)
    return scope.none if keys.empty?
    keys.map { |key| scope.where("custom_fields ->> ? = ?", key, installer_id.to_s) }.reduce(:or)
  end
end
```

- [ ] **Step 4: Replace the index view**

Replace `app/views/projects/index.html.erb` in full:

```erb
<h1>Proyectos</h1>

<%= form_with url: projects_path, method: :get, local: true, class: "row g-2 mb-4" do |form| %>
  <div class="col-auto">
    <%= form.label :project_type_id, "Tipo", class: "form-label" %>
    <%= form.select :project_type_id, @project_types.collect { |pt| [pt.name, pt.id] },
          { include_blank: "Todos", selected: params[:project_type_id] }, class: "form-select" %>
  </div>
  <div class="col-auto">
    <%= form.label :status, "Estado", class: "form-label" %>
    <%= form.select :status, @statuses, { include_blank: "Todos", selected: params[:status] }, class: "form-select" %>
  </div>
  <div class="col-auto">
    <%= form.label :installer_id, "Instalador", class: "form-label" %>
    <%= form.select :installer_id, @installers.collect { |i| [i.name, i.id] },
          { include_blank: "Todos", selected: params[:installer_id] }, class: "form-select" %>
  </div>
  <div class="col-auto align-self-end">
    <%= form.submit "Filtrar", class: "btn btn-primary" %>
  </div>
<% end %>

<% if @projects.none? %>
  <p>No hay proyectos con estos filtros.</p>
<% else %>
  <% content_for :head do %>
    <link href="https://cdn.jsdelivr.net/npm/frappe-gantt@0.6.1/dist/frappe-gantt.css" rel="stylesheet">
  <% end %>

  <%
    gantt_tasks = @projects.map do |project|
      first, last = project.gantt_window
      current = project.current_stage
      progress_values = project.project_stages.map(&:progress_percent)
      average_progress = progress_values.any? ? (progress_values.sum / progress_values.size.to_f).round : 0
      {
        id: project.id.to_s,
        name: project.name,
        start: first.to_s,
        end: last.to_s,
        progress: average_progress,
        edit_url: project_path(project),
        custom_class: "stage-color-#{current&.stage_template_id || 'none'}"
      }
    end
    gantt_colors = @projects.map do |project|
      template_id = project.current_stage&.stage_template_id || "none"
      color = project.current_stage&.stage_template&.color || "#6c757d"
      [template_id, color]
    end.uniq
  %>
  <style>
    <% gantt_colors.each do |template_id, color| %>
      .bar-wrapper.stage-color-<%= template_id %> .bar { fill: <%= color %>; }
    <% end %>
  </style>

  <div id="gantt" class="mb-4"></div>

  <script type="application/json" id="gantt-tasks"><%== gantt_tasks.to_json %></script>

  <script src="https://cdn.jsdelivr.net/npm/frappe-gantt@0.6.1/dist/frappe-gantt.min.js"></script>
  <script>
    document.addEventListener("DOMContentLoaded", function () {
      var tasks = JSON.parse(document.getElementById("gantt-tasks").textContent);
      if (tasks.length > 0) {
        var gantt = new Gantt("#gantt", tasks, {
          language: "es",
          on_click: function (task) { window.location = task.edit_url; },
          on_date_change: function () { gantt.refresh(tasks); },
          on_progress_change: function () { gantt.refresh(tasks); }
        });
      }
    });
  </script>

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
            <%= form_with(model: project, local: true, method: :patch, style: "display:inline-block") do |f| %>
              <%= f.hidden_field :status, value: "archived" %>
              <%= f.submit "Archivar", class: "btn btn-outline-danger btn-sm" %>
            <% end %>
          </td>
        </tr>
      <% end %>
    </tbody>
  </table>
<% end %>

<h2>Nuevo proyecto</h2>
<ul class="list-unstyled">
  <% ProjectType.all.each do |project_type| %>
    <li><%= link_to project_type.name, new_project_path(project_type_id: project_type.id), class: "btn btn-outline-primary btn-sm mb-1" %></li>
  <% end %>
</ul>
```

- [ ] **Step 5: Delete the dashboard action, view, and route**

```bash
rm app/views/projects/dashboard.html.erb
```

Edit `app/controllers/projects_controller.rb` — already done in Step 3 (the rewritten file has no `dashboard` method).

Edit `config/routes.rb` — remove this line (keep everything else unchanged):

```ruby
  get "projects/dashboard", to: "projects#dashboard", as: :dashboard_projects
```

So the routes file reads:

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

  resources :projects

  root "projects#index"
end
```

- [ ] **Step 6: Remove the "Gerencia" navbar link**

Edit `app/views/layouts/_navbar.html.erb`:

```erb
<nav class="navbar navbar-expand-lg navbar-light bg-light mb-4">
  <div class="container-fluid">
    <%= link_to "Nalakalu Proyectos", root_path, class: "navbar-brand" %>
    <div class="navbar-nav me-auto">
      <%= link_to "Proyectos", projects_path, class: "nav-link" %>
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

- [ ] **Step 7: Add read-only Spanish Gantt options to `show.html.erb`**

Edit `app/views/projects/show.html.erb` — replace only the closing `<script>` block (the rest of the file is unchanged):

```erb
<script src="https://cdn.jsdelivr.net/npm/frappe-gantt@0.6.1/dist/frappe-gantt.min.js"></script>
<script>
  document.addEventListener("DOMContentLoaded", function () {
    var tasks = JSON.parse(document.getElementById("gantt-tasks").textContent);
    if (tasks.length > 0) {
      var gantt = new Gantt("#gantt", tasks, {
        language: "es",
        on_click: function (task) { window.location.hash = "stage-" + task.id; },
        on_date_change: function () { gantt.refresh(tasks); },
        on_progress_change: function () { gantt.refresh(tasks); }
      });
    }
  });
</script>
```

- [ ] **Step 8: Update the navbar test**

Edit `test/controllers/navbar_test.rb` — remove the second test entirely, leaving:

```ruby
require "test_helper"

class NavbarTest < ActionDispatch::IntegrationTest
  test "navbar shows session-aware links when signed in" do
    sign_in users(:juan)
    get root_path
    assert_response :success
    assert_select "nav a[href=?]", projects_path
    assert_select "nav a[href=?]", admin_project_types_path
    assert_select "nav", /juan@example\.com/
  end
end
```

- [ ] **Step 9: Run the tests to verify they pass**

Run: `bin/rails test test/controllers/projects_controller_test.rb test/controllers/navbar_test.rb`
Expected: PASS (all tests)

- [ ] **Step 10: Run the full suite**

Run: `bin/rails test`
Expected: PASS — confirms nothing else references `dashboard_projects_path` or the deleted view.

Run: `grep -rn "dashboard_projects_path\|projects/dashboard\|management-gantt" app test config`
Expected: no output.

- [ ] **Step 11: Commit**

```bash
git add app/controllers/projects_controller.rb app/views/projects/index.html.erb app/views/projects/show.html.erb \
  config/routes.rb app/views/layouts/_navbar.html.erb test/controllers/projects_controller_test.rb \
  test/controllers/navbar_test.rb
git add -u app/views/projects/dashboard.html.erb
git commit -m "Merge Proyectos and Gerencia into one filterable home screen with a read-only Gantt"
```

---

### Task 2: Devise views in Spanish

**Files:**
- Create (via generator, then edit): `app/views/devise/sessions/new.html.erb`
- Create (via generator, then edit): `app/views/devise/registrations/new.html.erb`
- Create (via generator, then edit): `app/views/devise/registrations/edit.html.erb`
- Create (via generator, then edit): `app/views/devise/shared/_links.html.erb`
- Create (via generator, then edit): `app/views/devise/shared/_error_messages.html.erb`
- Delete (generated but unreachable — `User` has no `:confirmable`/`:recoverable`/`:lockable`): `app/views/devise/confirmations/`, `app/views/devise/passwords/`, `app/views/devise/unlocks/`, `app/views/devise/mailer/`
- Modify: `test/controllers/authentication_test.rb` (add Spanish-text assertions)

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: nothing consumed by Task 3 — Task 3's locale files are read by these views (`resource.errors.full_messages`, `f.label`) but neither task requires the other to exist first. Order here is arbitrary; this plan does Task 2 before Task 3 only because the view text is being hand-set anyway.

- [ ] **Step 1: Generate the Devise views**

Run: `bin/rails generate devise:views`
Expected output: creates `app/views/devise/{confirmations,mailer,passwords,registrations,sessions,shared,unlocks}/...`

- [ ] **Step 2: Delete the unreachable views**

`User` (`app/models/user.rb`) only has `devise :database_authenticatable, :registerable, :rememberable, :validatable` — no `:confirmable`, `:recoverable`, or `:lockable`, so their views and all mailer views are dead code:

```bash
rm -rf app/views/devise/confirmations app/views/devise/passwords app/views/devise/unlocks app/views/devise/mailer
```

- [ ] **Step 3: Translate `sessions/new.html.erb`**

Replace `app/views/devise/sessions/new.html.erb` in full:

```erb
<h2>Iniciar sesión</h2>

<%= form_for(resource, as: resource_name, url: session_path(resource_name)) do |f| %>
  <div class="field">
    <p><%= f.label :email, "Correo electrónico" %></p>
    <p><%= f.email_field :email, autofocus: true, autocomplete: "email" %></p>
  </div>

  <div class="field">
    <p><%= f.label :password, "Contraseña" %></p>
    <p><%= f.password_field :password, autocomplete: "current-password" %></p>
  </div>

  <% if devise_mapping.rememberable? %>
    <div class="field">
      <p><%= f.check_box :remember_me %></p>
      <p><%= f.label :remember_me, "Recordarme" %></p>
    </div>
  <% end %>

  <div class="actions">
    <%= f.submit "Iniciar sesión" %>
  </div>
<% end %>

<%= render "devise/shared/links" %>
```

- [ ] **Step 4: Translate `registrations/new.html.erb`**

Replace `app/views/devise/registrations/new.html.erb` in full:

```erb
<h2>Registrarse</h2>

<%= form_for(resource, as: resource_name, url: registration_path(resource_name)) do |f| %>
  <%= render "devise/shared/error_messages", resource: resource %>

  <div class="field">
    <p><%= f.label :email, "Correo electrónico" %></p>
    <p><%= f.email_field :email, autofocus: true, autocomplete: "email" %></p>
  </div>

  <div class="field">
    <p><%= f.label :password, "Contraseña" %></p>
    <% if @minimum_password_length %>
      <p><em>(mínimo <%= @minimum_password_length %> caracteres)</em></p>
    <% end %>
    <p><%= f.password_field :password, autocomplete: "new-password" %></p>
  </div>

  <div class="field">
    <p><%= f.label :password_confirmation, "Confirmación de contraseña" %></p>
    <p><%= f.password_field :password_confirmation, autocomplete: "new-password" %></p>
  </div>

  <div class="actions">
    <%= f.submit "Registrarse" %>
  </div>
<% end %>

<%= render "devise/shared/links" %>
```

- [ ] **Step 5: Translate `registrations/edit.html.erb`**

Replace `app/views/devise/registrations/edit.html.erb` in full:

```erb
<h2>Editar cuenta</h2>

<%= form_for(resource, as: resource_name, url: registration_path(resource_name), html: { method: :put }) do |f| %>
  <%= render "devise/shared/error_messages", resource: resource %>

  <div class="field">
    <p><%= f.label :email, "Correo electrónico" %></p>
    <p><%= f.email_field :email, autofocus: true, autocomplete: "email" %></p>
  </div>

  <div class="field">
    <p><%= f.label :password, "Contraseña" %> <i>(déjalo en blanco si no quieres cambiarla)</i></p>
    <p><%= f.password_field :password, autocomplete: "new-password" %></p>
    <% if @minimum_password_length %>
      <p><em>mínimo <%= @minimum_password_length %> caracteres</em></p>
    <% end %>
  </div>

  <div class="field">
    <p><%= f.label :password_confirmation, "Confirmación de contraseña" %></p>
    <p><%= f.password_field :password_confirmation, autocomplete: "new-password" %></p>
  </div>

  <div class="field">
    <p><%= f.label :current_password, "Contraseña actual" %> <i>(necesitamos tu contraseña actual para confirmar los cambios)</i></p>
    <p><%= f.password_field :current_password, autocomplete: "current-password" %></p>
  </div>

  <div class="actions">
    <%= f.submit "Actualizar" %>
  </div>
<% end %>

<h3>Cancelar mi cuenta</h3>

<div>¿Ya no la quieres? <%= button_to "Cancelar mi cuenta", registration_path(resource_name), data: { confirm: "¿Estás seguro?", turbo_confirm: "¿Estás seguro?" }, method: :delete %></div>

<%= link_to "Volver", :back %>
```

- [ ] **Step 6: Translate `shared/_links.html.erb`**

Replace `app/views/devise/shared/_links.html.erb` in full:

```erb
<%- if controller_name != 'sessions' %>
  <p><%= link_to "Iniciar sesión", new_session_path(resource_name) %></p>
<% end %>

<%- if devise_mapping.registerable? && controller_name != 'registrations' %>
  <p><%= link_to "Regístrate", new_registration_path(resource_name) %></p>
<% end %>
```

(Solo quedan los dos bloques alcanzables — `registerable` está habilitado; `recoverable`, `confirmable`, `lockable` y `omniauthable` no lo están en `User`, así que sus bloques del parcial original se eliminan en vez de traducirse: código muerto, no texto en inglés que arreglar.)

- [ ] **Step 7: Translate `shared/_error_messages.html.erb`**

Replace `app/views/devise/shared/_error_messages.html.erb` in full — no changes to the Ruby/ERB logic, only relies on the `errors.messages.not_saved` translation Task 3 supplies:

```erb
<% if resource.errors.any? %>
  <div id="error_explanation" data-turbo-temporary>
    <h2>
      <%= I18n.t("errors.messages.not_saved",
                 count: resource.errors.count,
                 resource: resource.class.model_name.human.downcase)
       %>
    </h2>
    <ul>
      <% resource.errors.full_messages.each do |message| %>
        <li><%= message %></li>
      <% end %>
    </ul>
  </div>
<% end %>
```

(This file's content is actually unchanged from the generated default — it already routes through `I18n.t`, so the translation lives in the locale file, not here. It's listed as "translated" because Task 3's `devise.es.yml` must supply `errors.messages.not_saved` for this to render in Spanish instead of showing "translation missing" — see Task 3, Step 3.)

- [ ] **Step 8: Add Spanish-text assertions to the authentication test**

Edit `test/controllers/authentication_test.rb`, add these tests inside the existing class:

```ruby
  test "sign-in page is in Spanish" do
    get new_user_session_path
    assert_response :success
    assert_select "h2", "Iniciar sesión"
    assert_select "input[value=?]", "Iniciar sesión"
  end

  test "sign-up page is in Spanish" do
    get new_user_registration_path
    assert_response :success
    assert_select "h2", "Registrarse"
    assert_select "input[value=?]", "Registrarse"
  end
```

- [ ] **Step 9: Run the tests**

Run: `bin/rails test test/controllers/authentication_test.rb`
Expected: PASS (5 tests: the 3 pre-existing plus the 2 new ones)

- [ ] **Step 10: Run the full suite**

Run: `bin/rails test`
Expected: PASS — no other test references the deleted Devise views/routes (this app never had `:confirmable`/`:recoverable`/`:lockable` routes, so nothing could have been testing them).

- [ ] **Step 11: Commit**

```bash
git add app/views/devise test/controllers/authentication_test.rb
git commit -m "Translate Devise's sign-in/sign-up/account views to Spanish"
```

---

### Task 3: Spanish locale files for validation messages, `default_locale`, cleanup

**Files:**
- Create: `config/locales/es.yml`
- Create: `config/locales/devise.es.yml`
- Modify: `config/application.rb` (set `config.i18n.default_locale`)
- Delete: `config/locales/en.yml` (only contained the unused `hello` key)

**Interfaces:**
- Consumes: nothing from Tasks 1/2.
- Produces: `es.errors.messages.not_saved` — required by Task 2's `devise/shared/_error_messages.html.erb` (already committed; this task supplies the translation it reads). If Task 3 runs before Task 2 in a different ordering, this dependency still resolves correctly since both are static locale/view files with no load-order coupling — Rails loads all of `config/locales/*.yml` at boot regardless of which file was added first.

- [ ] **Step 1: Confirm the `hello` key is unused, then delete `en.yml`**

Run: `grep -rn '"hello"\|:hello\b' app/`
Expected: no output (confirms it's safe to delete).

```bash
rm config/locales/en.yml
```

- [ ] **Step 2: Set the default locale**

Edit `config/application.rb`:

```ruby
require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module FeatureProjectTypesDinamicos
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.2

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    config.i18n.default_locale = :es
  end
end
```

- [ ] **Step 3: Add `config/locales/devise.es.yml`**

Mechanical translation of `config/locales/devise.en.yml` (same keys, same interpolation placeholders, `es:` root instead of `en:`):

```yaml
# Additional translations at https://github.com/heartcombo/devise/wiki/I18n

es:
  devise:
    confirmations:
      confirmed: "Tu correo electrónico se confirmó correctamente."
      send_instructions: "En unos minutos recibirás un correo con instrucciones para confirmar tu dirección de correo electrónico."
      send_paranoid_instructions: "Si tu correo electrónico existe en nuestra base de datos, recibirás un correo con instrucciones para confirmarlo en unos minutos."
    failure:
      already_authenticated: "Ya has iniciado sesión."
      inactive: "Tu cuenta todavía no ha sido activada."
      invalid: "%{authentication_keys} o contraseña inválidos."
      locked: "Tu cuenta está bloqueada."
      last_attempt: "Te queda un intento antes de que tu cuenta sea bloqueada."
      not_found_in_database: "%{authentication_keys} o contraseña inválidos."
      timeout: "Tu sesión expiró. Por favor inicia sesión nuevamente para continuar."
      unauthenticated: "Necesitas iniciar sesión o registrarte antes de continuar."
      unconfirmed: "Tienes que confirmar tu correo electrónico antes de continuar."
    mailer:
      confirmation_instructions:
        subject: "Instrucciones de confirmación"
      reset_password_instructions:
        subject: "Instrucciones para restablecer tu contraseña"
      unlock_instructions:
        subject: "Instrucciones para desbloquear tu cuenta"
      email_changed:
        subject: "Correo electrónico modificado"
      password_change:
        subject: "Contraseña modificada"
    omniauth_callbacks:
      failure: "No se pudo autenticar desde %{kind} porque \"%{reason}\"."
      success: "Autenticación exitosa desde la cuenta de %{kind}."
    passwords:
      no_token: "No puedes acceder a esta página sin venir desde un correo de recuperación de contraseña. Si vienes desde uno, asegúrate de haber usado la URL completa provista."
      send_instructions: "En unos minutos recibirás un correo con instrucciones para restablecer tu contraseña."
      send_paranoid_instructions: "Si tu correo electrónico existe en nuestra base de datos, recibirás un enlace de recuperación en unos minutos."
      updated: "Tu contraseña se cambió correctamente. Ya iniciaste sesión."
      updated_not_active: "Tu contraseña se cambió correctamente."
    registrations:
      destroyed: "¡Hasta pronto! Tu cuenta se canceló correctamente. Esperamos verte de nuevo pronto."
      signed_up: "¡Bienvenido! Te registraste correctamente."
      signed_up_but_inactive: "Te registraste correctamente. Sin embargo, no pudimos iniciar tu sesión porque tu cuenta todavía no está activada."
      signed_up_but_locked: "Te registraste correctamente. Sin embargo, no pudimos iniciar tu sesión porque tu cuenta está bloqueada."
      signed_up_but_unconfirmed: "Se envió un mensaje con un enlace de confirmación a tu correo electrónico. Sigue el enlace para activar tu cuenta."
      update_needs_confirmation: "Actualizaste tu cuenta correctamente, pero necesitamos verificar tu nuevo correo electrónico. Revisa tu correo y sigue el enlace de confirmación."
      updated: "Tu cuenta se actualizó correctamente."
      updated_but_not_signed_in: "Tu cuenta se actualizó correctamente, pero como tu contraseña cambió, necesitas iniciar sesión de nuevo."
    sessions:
      signed_in: "Iniciaste sesión correctamente."
      signed_out: "Cerraste sesión correctamente."
      already_signed_out: "Cerraste sesión correctamente."
    unlocks:
      send_instructions: "En unos minutos recibirás un correo con instrucciones para desbloquear tu cuenta."
      send_paranoid_instructions: "Si tu cuenta existe, recibirás un correo con instrucciones para desbloquearla en unos minutos."
      unlocked: "Tu cuenta se desbloqueó correctamente. Inicia sesión para continuar."
  errors:
    messages:
      already_confirmed: "ya había sido confirmado, intenta iniciar sesión"
      confirmation_period_expired: "necesita confirmarse dentro de %{period}, por favor solicita uno nuevo"
      expired: "expiró, por favor solicita uno nuevo"
      not_found: "no encontrado"
      not_locked: "no estaba bloqueado"
      not_saved:
        one: "1 error impidió guardar este %{resource}:"
        other: "%{count} errores impidieron guardar este %{resource}:"
```

- [ ] **Step 4: Add `config/locales/es.yml`**

```yaml
# ponytail: covers only the generic ActiveRecord/ActiveModel error keys and
# attribute names this app actually triggers today (confirmed by reading
# every `validates` call in app/models/). A new model with an untranslated
# validator will show its message in English until a key is added here —
# that's an accepted gap, not a bug, per the design spec (no rails-i18n /
# devise-i18n dependency added just for exhaustive coverage).
es:
  activerecord:
    models:
      user: "usuario"
    attributes:
      user:
        email: "Correo electrónico"
        password: "Contraseña"
        password_confirmation: "Confirmación de contraseña"
      project_type:
        name: "Nombre"
        slug: "Slug"
      field_definition:
        key: "Clave"
        label: "Etiqueta"
        data_type: "Tipo de dato"
      stage_template:
        name: "Nombre"
        color: "Color"
      project:
        name: "Nombre"
      project_stage:
        name: "Nombre"
        progress_percent: "Porcentaje de avance"
      installer:
        name: "Nombre"
  errors:
    messages:
      blank: "no puede estar en blanco"
      taken: "ya está en uso"
      invalid: "no es válido"
      too_short:
        one: "es demasiado corto (mínimo 1 carácter)"
        other: "es demasiado corto (mínimo %{count} caracteres)"
      confirmation: "no coincide con %{attribute}"
      inclusion: "no está incluido en la lista"
```

(`not_saved` lives in `devise.es.yml`, Step 3 — it's Devise's own key, already present in the untranslated `devise.en.yml`; it is not duplicated here to avoid two files defining the same key.)

- [ ] **Step 5: Confirm no test asserts on exact English validation-message text**

Run: `grep -rn "can't be blank\|has already been taken\|is not included in the list\|is invalid\|doesn't match\|is too short" test/`
Expected: no output. (Already confirmed during planning — every model test in this suite asserts only `valid?`/`invalid?`/`errors[:field].any?`, never the literal English message text, so switching `default_locale` to `:es` needs no test-file changes. This step re-confirms it wasn't invalidated by Tasks 1-2's edits before you commit.)

- [ ] **Step 6: Run the full suite**

Run: `bin/rails test`
Expected: PASS.

- [ ] **Step 7: Manual verification**

Run: `bin/rails server` and in the browser:
- Visit `/users/sign_in` and `/users/sign_up` — confirm all text is Spanish.
- Submit the sign-up form with a blank password — confirm the error box header and message list are in Spanish (this exercises `devise.es.yml`'s `not_saved` plus `es.yml`'s `blank`/`too_short` together).
- Create an `Installer` with a blank name via `/admin/installers/new` — confirm the inline error is in Spanish ("Nombre no puede estar en blanco").

- [ ] **Step 8: Commit**

```bash
git add config/locales/es.yml config/locales/devise.es.yml config/application.rb
git add -u config/locales/en.yml
git commit -m "Add Spanish locale files, set default_locale, remove unused en.yml"
```

---

## Final verification

- [ ] Run `bin/rails test` once more after all three tasks — expect a clean pass.
- [ ] `grep -rn "dashboard_projects_path\|management-gantt\|devise/confirmations\|devise/passwords\|devise/unlocks" app test config` returns nothing.
- [ ] Manually load `/` (redirects to sign-in if not authenticated), sign in, confirm the home screen shows filters + Gantt + table together with no "Gerencia" link in the nav, confirm dragging a Gantt bar snaps back, confirm the installer filter narrows the list.
