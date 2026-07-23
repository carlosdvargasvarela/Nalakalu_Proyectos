# Pantalla "Seguimiento" — edición en bloque de etapas por tipo de proyecto — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a new screen where every non-archived project of a chosen project type shows its own editable stage table (Etapa/Inicio/Fin/% Avance) on one page, closing the gap back to the original Excel sheet's multi-order view — without opening each project individually.

**Architecture:** One new controller action (`ProjectsController#tracker`), one new view, one new route, one new nav link. No new persistence mechanism — each project block is its own `form_with model: project` using the same `accepts_nested_attributes_for :project_stages` already wired from an earlier round; saving one project's table doesn't touch any other project's.

**Tech Stack:** Ruby on Rails, Minitest + fixtures. No new JS, no Gantt on this page (deliberately — N projects would mean N chart instances; each block links to the full detail page instead).

## Global Constraints

- No new gems, no new persistence/endpoint — reuse `ProjectsController#update` and `Project#project_stages_attributes=` exactly as they exist today.
- The route must be declared before `resources :projects` (same reasoning as the removed `dashboard` route from an earlier round): a literal path segment like `/projects/seguimiento` must not be shadowed by `resources :projects`' `/projects/:id` match order-dependent routing.
- Archived projects are excluded by default, consistent with `projects#index`'s default behavior.

---

### Task 1: `Seguimiento` screen

**Files:**
- Modify: `config/routes.rb` (new route)
- Modify: `app/controllers/projects_controller.rb` (new `tracker` action)
- Create: `app/views/projects/tracker.html.erb`
- Modify: `app/views/layouts/_navbar.html.erb` (new nav link)
- Modify: `test/controllers/projects_controller_test.rb` (new tests)
- Modify: `test/controllers/navbar_test.rb` (new assertion)

**Interfaces:**
- Consumes: `ProjectType#field_definitions` (`show_in_gantt`, unchanged), `Project#project_stages`/`accepts_nested_attributes_for` (unchanged), `ApplicationHelper#status_badge` (unchanged, from an earlier round).
- Produces: `tracker_projects_path` route — no later task depends on it, this is the only task in this plan.

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

  get "projects/seguimiento", to: "projects#tracker", as: :tracker_projects
  resources :projects

  root "projects#index"
end
```

- [ ] **Step 2: Write the failing controller tests**

Add to `test/controllers/projects_controller_test.rb`, inside the existing test class:

```ruby
  test "tracker defaults to the first project type when none is given" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get tracker_projects_path
    assert_response :success
    assert_select "body", /#{project.name}/
  end

  test "tracker filters by the given project type" do
    other_type = ProjectType.create!(name: "Mantenimiento", slug: "mantenimiento")
    torre = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    otro = Project.create!(project_type: other_type, name: "Proyecto Otro Tipo", custom_fields: {})

    get tracker_projects_path, params: { project_type_id: other_type.id }
    assert_response :success
    assert_match(/#{otro.name}/, response.body)
    assert_no_match(/#{torre.name}/, response.body)
  end

  test "tracker excludes archived projects" do
    activo = Project.create!(project_type: project_types(:instalaciones), name: "Activo", custom_fields: {})
    Project.create!(
      project_type: project_types(:instalaciones), name: "Archivado", custom_fields: {}, status: "archived"
    )
    get tracker_projects_path
    assert_response :success
    assert_match(/#{activo.name}/, response.body)
    assert_no_match(/Archivado/, response.body)
  end

  test "tracker shows each project's show_in_gantt fields and an editable stage table" do
    project = Project.create!(
      project_type: project_types(:instalaciones), name: "Torre Norte",
      custom_fields: { cliente: "Acme S.A." }
    )
    get tracker_projects_path
    assert_response :success
    assert_select "body", /Cliente/
    assert_select "body", /Acme S\.A\./
    assert_select "input[name*='[start_date]']", count: project.project_stages.count
  end

  test "tracker saves a project's stages independently of other projects" do
    torre = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    otra = Project.create!(project_type: project_types(:instalaciones), name: "Otra Torre", custom_fields: {})
    stage = torre.project_stages.order(:id).first
    otra_stage = otra.project_stages.order(:id).first

    patch project_path(torre), params: {
      project: { project_stages_attributes: { "0" => { id: stage.id, progress_percent: 80 } } }
    }

    assert_redirected_to project_path(torre)
    assert_equal 80, stage.reload.progress_percent
    assert_equal 0, otra_stage.reload.progress_percent
  end

  test "tracker shows a message when there are no project types at all" do
    ProjectType.destroy_all
    get tracker_projects_path
    assert_response :success
    assert_select "body", /No hay tipos de proyecto configurados todavía/
  end
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: FAIL — no `tracker` route/action/view exists yet (routing error).

- [ ] **Step 4: Add the controller action**

Edit `app/controllers/projects_controller.rb` — add this public method, right after `index`:

```ruby
  def tracker
    @project_types = ProjectType.all
    @project_type = ProjectType.find_by(id: params[:project_type_id]) || ProjectType.first
    @projects = if @project_type
      Project.where(project_type: @project_type).where.not(status: "archived")
             .includes(project_stages: :stage_template).order(:name)
    else
      Project.none
    end
  end
```

- [ ] **Step 5: Create the view**

Create `app/views/projects/tracker.html.erb`:

```erb
<h1>Seguimiento</h1>

<%= form_with url: tracker_projects_path, method: :get, local: true, class: "row g-2 mb-4" do |form| %>
  <div class="col-auto">
    <%= form.label :project_type_id, "Tipo", class: "form-label" %>
    <%= form.select :project_type_id, @project_types.collect { |pt| [pt.name, pt.id] },
          { selected: @project_type&.id }, class: "form-select" %>
  </div>
  <div class="col-auto align-self-end">
    <%= form.submit "Ver", class: "btn btn-primary" %>
  </div>
<% end %>

<% if @project_type.nil? %>
  <p>No hay tipos de proyecto configurados todavía.</p>
<% elsif @projects.none? %>
  <p>No hay proyectos de este tipo.</p>
<% else %>
  <% gantt_fields = @project_type.field_definitions.where(show_in_gantt: true).order(:position) %>
  <% @projects.each do |project| %>
    <div class="card mb-4">
      <div class="card-header d-flex justify-content-between align-items-center">
        <div>
          <%= link_to project.name, project_path(project), class: "fw-bold text-decoration-none" %>
          <% gantt_fields.each do |field| %>
            <span class="text-muted ms-3"><%= field.label %>: <%= project.custom_fields[field.key] %></span>
          <% end %>
        </div>
        <%= status_badge(project.status) %>
      </div>
      <div class="card-body">
        <%= form_with model: project do |f| %>
          <table class="table table-sm table-bordered w-auto mb-0">
            <thead>
              <tr><th>Etapa</th><th>Inicio</th><th>Fin</th><th>% Avance</th></tr>
            </thead>
            <tbody>
              <%= f.fields_for :project_stages, project.project_stages.includes(:stage_template).order(:id) do |sf| %>
                <tr>
                  <td><%= sf.object.name %></td>
                  <td><%= sf.hidden_field :id %><%= sf.date_field :start_date, class: "form-control form-control-sm" %></td>
                  <td><%= sf.date_field :end_date, class: "form-control form-control-sm" %></td>
                  <td><%= sf.number_field :progress_percent, min: 0, max: 100, class: "form-control form-control-sm" %></td>
                </tr>
              <% end %>
            </tbody>
          </table>
          <%= f.submit "Guardar", class: "btn btn-primary btn-sm mt-3" %>
        <% end %>
      </div>
    </div>
  <% end %>
<% end %>
```

- [ ] **Step 6: Run the controller tests to verify they pass**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: PASS (all tests)

- [ ] **Step 7: Add the nav link and its test**

Edit `app/views/layouts/_navbar.html.erb`:

```erb
<nav class="navbar navbar-expand-lg navbar-light bg-light mb-4">
  <div class="container-fluid">
    <%= link_to "Nalakalu Proyectos", root_path, class: "navbar-brand" %>
    <div class="navbar-nav me-auto">
      <%= link_to "Proyectos", projects_path, class: "nav-link" %>
      <%= link_to "Seguimiento", tracker_projects_path, class: "nav-link" %>
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

Add to `test/controllers/navbar_test.rb`, inside the existing test class:

```ruby
  test "navbar includes a link to Seguimiento" do
    sign_in users(:juan)
    get root_path
    assert_response :success
    assert_select "nav a[href=?]", tracker_projects_path
  end
```

- [ ] **Step 8: Run the tests to verify they pass**

Run: `bin/rails test test/controllers/projects_controller_test.rb test/controllers/navbar_test.rb`
Expected: PASS (all tests)

- [ ] **Step 9: Run the full suite**

Run: `bin/rails test`
Expected: PASS

- [ ] **Step 10: Manual verification**

Run: `bin/rails server`, click "Seguimiento" in the nav:
- Confirm it defaults to a project type with projects and shows one card per project.
- Confirm each card shows the project's Cliente/Instalador (or whatever fields are marked `show_in_gantt`) and an editable stage table.
- Edit a date/progress in one project's table, click its "Guardar" — confirm only that project's stage changed (check another project's table still shows its old values after the page reloads).
- Switch the type filter — confirm the list of cards updates accordingly.
- Confirm archived projects don't appear.

- [ ] **Step 11: Commit**

```bash
git add config/routes.rb app/controllers/projects_controller.rb app/views/projects/tracker.html.erb \
  app/views/layouts/_navbar.html.erb test/controllers/projects_controller_test.rb test/controllers/navbar_test.rb
git commit -m "Add Seguimiento screen: bulk-editable stage tables grouped by project type"
```

---

## Final verification

- [ ] Run `bin/rails test` once more — expect a clean pass.
- [ ] `bin/rails routes -g tracker` shows the new route mapped before `/projects/:id`, confirming ordering is correct.
