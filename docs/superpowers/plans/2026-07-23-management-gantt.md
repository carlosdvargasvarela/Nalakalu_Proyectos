# Vista gerencial multi-proyecto, edición visible y color por subproceso — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a filterable, one-bar-per-project management Gantt dashboard; expose the already-built "edit project" form via visible links; make each subprocess's Gantt bar color admin-configurable.

**Architecture:** `Project` gains computed methods (`start_date`/`end_date`/`gantt_window`/`current_stage`) derived from its `project_stages` — no new columns on `Project`. `StageTemplate` gains a `color` column. The existing per-project Gantt (`projects/show.html.erb`) is extended to color each stage's bar by its `stage_template.color`. A new `projects#dashboard` action reuses the identical Frappe Gantt CDN pattern, one bar per project, colored by that project's current stage.

**Tech Stack:** Rails 7.2.3, Frappe Gantt 0.6.1 (CDN, already in use), Minitest, existing Devise auth (all routes in this plan require login, already enforced globally).

## Global Constraints

- `StageTemplate#color` is a hex string (`#rrggbb`, 6 digits), default `"#6c757d"` (Bootstrap's `secondary` gray).
- `Project#current_stage` = the most-advanced started stage (`progress_percent > 0`, highest `id`), or the first stage (lowest `id`) if none has started, or `nil` if the project has no stages. All four new `Project` methods (`start_date`, `end_date`, `gantt_window`, `current_stage`) operate on the in-memory `project_stages` association (`.map`/`.select`/`.max_by`/`.min_by`, never `.minimum`/`.maximum`/`.where`) so that a controller preloading `project_stages` with `.includes` avoids N+1 queries when these methods are called per-project in a loop (the dashboard does exactly this).
- Bar coloring (both the existing per-project Gantt and the new dashboard) uses Frappe Gantt's `custom_class` + a server-generated inline `<style>` block mapping `.bar-wrapper.stage-color-<stage_template_id> .bar { fill: <color>; }` — Frappe Gantt 0.6.1 has no direct per-task color field in the task data.
- The dashboard route (`get "projects/dashboard"`) must be declared **before** `resources :projects` in `config/routes.rb`, or `/projects/dashboard` gets swallowed by the `show` action's `/projects/:id`.
- Status filter options come from `Project.distinct.pluck(:status)` — no new enum/constant, since `status` is currently a free string column with no fixed value set anywhere in the codebase.
- Every task must leave the full `bin/rails test` suite green. Starting count: 46.

---

## File Structure

| File | Responsibility |
|---|---|
| `app/models/project.rb` | adds `start_date`, `end_date`, `gantt_window`, `current_stage` |
| `db/migrate/..._add_color_to_stage_templates.rb` | `color` column |
| `app/models/stage_template.rb` | `color` validation |
| `app/views/admin/stage_templates/_form.html.erb` | color picker field |
| `app/views/projects/index.html.erb` | "Editar" link per row |
| `app/views/projects/show.html.erb` | "Editar" link + stage bar coloring |
| `config/routes.rb` | `GET /projects/dashboard` |
| `app/controllers/projects_controller.rb` | `dashboard` action |
| `app/views/projects/dashboard.html.erb` | filterable multi-project Gantt |
| `app/views/layouts/_navbar.html.erb` | "Gerencia" link |

---

## Task 1: Project computed date/stage methods

**Files:**
- Modify: `app/models/project.rb`
- Test: `test/models/project_test.rb`

**Interfaces:**
- Consumes: `Project#project_stages` (existing association).
- Produces: `Project#start_date`, `#end_date`, `#gantt_window` (returns `[start_date, end_date]`), `#current_stage` (returns a `ProjectStage` or `nil`) — all four consumed by Task 5 (the dashboard). Task 4 does not depend on this task — it colors each stage bar directly from `stage.stage_template.color`, with no `Project`-level aggregation.

- [ ] **Step 1: Write the failing tests**

Edit `test/models/project_test.rb`, add at the end of the class (before the final `end`):

```ruby
  test "start_date and end_date reflect the earliest and latest stage dates" do
    project = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: {})
    stages = project.project_stages.order(:id).to_a
    stages[0].update!(start_date: Date.new(2026, 1, 10), end_date: Date.new(2026, 1, 20))
    stages[1].update!(start_date: Date.new(2026, 1, 5), end_date: Date.new(2026, 1, 15))
    stages[2].update!(start_date: Date.new(2026, 2, 1), end_date: Date.new(2026, 2, 28))

    assert_equal Date.new(2026, 1, 5), project.start_date
    assert_equal Date.new(2026, 2, 28), project.end_date
    assert_equal [Date.new(2026, 1, 5), Date.new(2026, 2, 28)], project.gantt_window
  end

  test "gantt_window falls back to a one-week window from created_at when no stage has dates" do
    project = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: {})
    first, last = project.gantt_window
    assert_equal project.created_at.to_date, first
    assert_equal first + 7.days, last
  end

  test "current_stage is the most advanced started stage, or the first stage if none started" do
    project = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: {})
    stages = project.project_stages.order(:id).to_a
    assert_equal stages.first, project.current_stage

    stages[0].update!(progress_percent: 100)
    stages[1].update!(progress_percent: 40)
    assert_equal stages[1], project.reload.current_stage
  end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bin/rails test test/models/project_test.rb
```

Expected: FAIL — `undefined method 'start_date'` (and similarly for the other two tests).

- [ ] **Step 3: Add the methods**

Edit `app/models/project.rb` — add these public methods right after `belongs_to`/`has_many`, before `validates`:

```ruby
class Project < ApplicationRecord
  belongs_to :project_type
  has_many :project_stages, dependent: :destroy

  validates :name, presence: true
  validate :custom_fields_match_definitions
  after_create :build_stages_from_template

  def start_date
    project_stages.map(&:start_date).compact.min
  end

  def end_date
    project_stages.map(&:end_date).compact.max
  end

  def gantt_window
    first = start_date || created_at.to_date
    last = end_date || (first + 7.days)
    [first, last]
  end

  def current_stage
    project_stages.select { |stage| stage.progress_percent > 0 }.max_by(&:id) || project_stages.min_by(&:id)
  end

  private
```

(This only adds the four new methods and a `private` line right before the existing `def build_stages_from_template` — the rest of the file is unchanged.)

- [ ] **Step 4: Run test to verify it passes**

```bash
bin/rails test test/models/project_test.rb
```

Expected: PASS (8 runs — 5 existing + 3 new — 0 failures).

- [ ] **Step 5: Run the full suite to confirm no regressions**

```bash
bin/rails test
```

Expected: all green (49 runs).

- [ ] **Step 6: Commit**

```bash
git add app/models/project.rb test/models/project_test.rb
git commit -m "Add Project#start_date/#end_date/#gantt_window/#current_stage"
```

---

## Task 2: StageTemplate#color

**Files:**
- Create: `db/migrate/<ts>_add_color_to_stage_templates.rb`
- Modify: `app/models/stage_template.rb`
- Modify: `app/views/admin/stage_templates/_form.html.erb`
- Test: `test/models/stage_template_test.rb`

**Interfaces:**
- Consumes: nothing new.
- Produces: `StageTemplate#color` (string, hex) — consumed by Task 4 (per-project Gantt) and Task 5 (dashboard).

- [ ] **Step 1: Generate the migration**

```bash
bin/rails generate migration AddColorToStageTemplates
```

Edit the generated file (`db/migrate/<ts>_add_color_to_stage_templates.rb`):

```ruby
class AddColorToStageTemplates < ActiveRecord::Migration[7.2]
  def change
    add_column :stage_templates, :color, :string, null: false, default: "#6c757d"
  end
end
```

- [ ] **Step 2: Write the failing tests**

Edit `test/models/stage_template_test.rb`, add at the end of the class (before the final `end`):

```ruby
  test "valid with default color" do
    stage = StageTemplate.new(project_type: project_types(:instalaciones), name: "Producción", position: 3)
    assert stage.valid?
    assert_equal "#6c757d", stage.color
  end

  test "invalid with a malformed color" do
    stage = StageTemplate.new(
      project_type: project_types(:instalaciones), name: "Producción", position: 3, color: "blue"
    )
    assert_not stage.valid?
  end
```

- [ ] **Step 3: Run migration and test to verify it fails**

```bash
bin/rails db:migrate
bin/rails test test/models/stage_template_test.rb
```

Expected: FAIL — the malformed-color test fails because there's no validation yet (a `StageTemplate` with `color: "blue"` is currently valid).

- [ ] **Step 4: Add the validation**

Edit `app/models/stage_template.rb`:

```ruby
class StageTemplate < ApplicationRecord
  belongs_to :project_type

  validates :name, presence: true
  validates :color, format: { with: /\A#[0-9a-fA-F]{6}\z/, message: "debe ser un color hexadecimal (ej. #6c757d)" }
end
```

- [ ] **Step 5: Add the color picker to the admin form**

Edit `app/views/admin/stage_templates/_form.html.erb` — add before `<%= form.submit %>`:

```erb
  <div class="mb-3">
    <%= form.label :color, class: "form-label" %>
    <%= form.color_field :color, class: "form-control form-control-color" %>
  </div>
```

- [ ] **Step 6: Run test to verify it passes**

```bash
bin/rails test test/models/stage_template_test.rb
```

Expected: PASS (5 runs — 3 existing + 2 new — 0 failures).

- [ ] **Step 7: Run the full suite to confirm no regressions**

```bash
bin/rails test
```

Expected: all green (51 runs).

- [ ] **Step 8: Commit**

```bash
git add db/migrate db/schema.rb app/models/stage_template.rb app/views/admin/stage_templates/_form.html.erb \
  test/models/stage_template_test.rb
git commit -m "Add StageTemplate#color, admin-editable"
```

---

## Task 3: Visible "Editar" links for projects

**Files:**
- Modify: `app/views/projects/index.html.erb`
- Modify: `app/views/projects/show.html.erb`
- Test: `test/controllers/projects_controller_test.rb`

**Interfaces:**
- Consumes: `edit_project_path` (existing route, `projects#edit`/`#update` already implemented, never linked from any view until this task).
- Produces: nothing consumed by later tasks — purely additive UI.

- [ ] **Step 1: Write the failing tests**

Edit `test/controllers/projects_controller_test.rb`, add at the end of the class (before the final `end`):

```ruby
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
```

- [ ] **Step 2: Run to verify it fails**

```bash
bin/rails test test/controllers/projects_controller_test.rb
```

Expected: FAIL — neither `assert_select` finds a matching link (no "Editar" link exists in either view yet).

- [ ] **Step 3: Add the link to the index table**

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
        <td><%= link_to "Editar", edit_project_path(project), class: "btn btn-outline-secondary btn-sm" %></td>
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

- [ ] **Step 4: Add the link to the show page**

Edit `app/views/projects/show.html.erb` — replace the first two lines:

```erb
<h1><%= @project.name %></h1>
<p class="text-muted">Tipo: <%= @project.project_type.name %></p>
```

with:

```erb
<h1><%= @project.name %></h1>
<%= link_to "Editar", edit_project_path(@project), class: "btn btn-outline-secondary btn-sm mb-2" %>
<p class="text-muted">Tipo: <%= @project.project_type.name %></p>
```

- [ ] **Step 5: Run test to verify it passes**

```bash
bin/rails test test/controllers/projects_controller_test.rb
```

Expected: PASS (9 runs — 7 existing + 2 new — 0 failures).

- [ ] **Step 6: Run the full suite to confirm no regressions**

```bash
bin/rails test
```

Expected: all green (53 runs).

- [ ] **Step 7: Commit**

```bash
git add app/views/projects/index.html.erb app/views/projects/show.html.erb test/controllers/projects_controller_test.rb
git commit -m "Add visible Editar links to projects index and show"
```

---

## Task 4: Color the per-project Gantt bars by stage_template

**Files:**
- Modify: `app/views/projects/show.html.erb`
- Test: `test/controllers/projects_controller_test.rb`

**Interfaces:**
- Consumes: `StageTemplate#color` (Task 2), `ProjectStage#stage_template` (existing).
- Produces: nothing consumed by later tasks — this task only touches the per-project view; Task 5 repeats the same pattern independently for the dashboard (not by extracting a shared helper — see note in Task 5).

- [ ] **Step 1: Write the failing test**

Edit `test/controllers/projects_controller_test.rb`, add at the end of the class (before the final `end`):

```ruby
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
```

- [ ] **Step 2: Run to verify it fails**

```bash
bin/rails test test/controllers/projects_controller_test.rb
```

Expected: FAIL — no `<style>` block with `.bar-wrapper.stage-color-N` rules exists yet.

- [ ] **Step 3: Wire the coloring into the Gantt task generation**

Edit `app/views/projects/show.html.erb` — replace the Ruby block and the `<script type="application/json" id="gantt-tasks">` line with:

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
      edit_url: edit_project_project_stage_path(@project, stage),
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
```

(Only the Ruby block gains `.includes(:stage_template)`, the `custom_class` key, the `stage_colors` computation, and the `<style>` block right before the existing `<script id="gantt-tasks">` line — everything else in the file, including the inline `<script>` that instantiates `Gantt(...)`, is unchanged.)

- [ ] **Step 4: Run test to verify it passes**

```bash
bin/rails test test/controllers/projects_controller_test.rb
```

Expected: PASS (10 runs — 9 existing + 1 new — 0 failures).

- [ ] **Step 5: Run the full suite to confirm no regressions**

```bash
bin/rails test
```

Expected: all green (54 runs).

- [ ] **Step 6: Commit**

```bash
git add app/views/projects/show.html.erb test/controllers/projects_controller_test.rb
git commit -m "Color per-project Gantt bars by their stage_template's color"
```

---

## Task 5: Management dashboard (filterable multi-project Gantt)

**Files:**
- Modify: `config/routes.rb`
- Modify: `app/controllers/projects_controller.rb`
- Create: `app/views/projects/dashboard.html.erb`
- Modify: `app/views/layouts/_navbar.html.erb`
- Test: `test/controllers/projects_controller_test.rb`, `test/controllers/navbar_test.rb`

**Interfaces:**
- Consumes: `Project#gantt_window`, `Project#current_stage` (Task 1), `StageTemplate#color` (Task 2).
- Produces: `dashboard_projects_path` — consumed by the navbar link, no other task depends on it.

Note: this task repeats the same `custom_class` + `<style>` coloring pattern from Task 4, applied to whole projects instead of individual stages. This is intentional duplication, not an oversight — the two blocks operate on different collections (`ProjectStage` vs `Project`) with different color-resolution rules (`stage.stage_template.color` directly vs `project.current_stage&.stage_template&.color`), so a shared helper would need a lookup-function parameter to stay correct, which is more machinery than the ~6 lines it would save. Revisit only if a third Gantt view is added.

- [ ] **Step 1: Add the route**

Edit `config/routes.rb` — add the dashboard route immediately before `resources :projects` (order matters: it must come first so `/projects/dashboard` isn't captured by `/projects/:id`):

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
  end

  get "projects/dashboard", to: "projects#dashboard", as: :dashboard_projects
  resources :projects do
    resources :project_stages, only: [:edit, :update]
  end

  root "projects#index"
end
```

- [ ] **Step 2: Write the failing tests**

Edit `test/controllers/projects_controller_test.rb`, add at the end of the class (before the final `end`):

```ruby
  test "dashboard shows one row per project across all types by default" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get dashboard_projects_path
    assert_response :success
    assert_select "script#management-gantt-tasks", text: /#{project.name}/
  end

  test "dashboard filters by project_type" do
    other_type = ProjectType.create!(name: "Mantenimiento", slug: "mantenimiento")
    torre = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    otro = Project.create!(project_type: other_type, name: "Proyecto Otro Tipo", custom_fields: {})

    get dashboard_projects_path, params: { project_type_id: other_type.id }
    assert_response :success
    assert_match(/#{otro.name}/, response.body)
    assert_no_match(/#{torre.name}/, response.body)
  end

  test "dashboard filters by status" do
    torre = Project.create!(
      project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {}, status: "active"
    )
    vieja = Project.create!(
      project_type: project_types(:instalaciones), name: "Torre Vieja", custom_fields: {}, status: "archived"
    )

    get dashboard_projects_path, params: { status: "archived" }
    assert_response :success
    assert_match(/#{vieja.name}/, response.body)
    assert_no_match(/#{torre.name}/, response.body)
  end

  test "dashboard shows a message when no projects match the filters" do
    get dashboard_projects_path, params: { status: "nonexistent-status" }
    assert_response :success
    assert_select "body", /No hay proyectos con estos filtros/
  end
```

Edit `test/controllers/navbar_test.rb`, add at the end of the class (before the final `end`):

```ruby
  test "navbar includes a link to the management dashboard" do
    sign_in users(:juan)
    get root_path
    assert_response :success
    assert_select "nav a[href=?]", dashboard_projects_path
  end
```

- [ ] **Step 3: Run to verify it fails**

```bash
bin/rails test test/controllers/projects_controller_test.rb test/controllers/navbar_test.rb
```

Expected: FAIL — `dashboard_projects_path` route doesn't resolve to a working action yet (`ProjectsController#dashboard` doesn't exist), and the navbar has no "Gerencia" link.

- [ ] **Step 4: Add the controller action**

Edit `app/controllers/projects_controller.rb` — add the `dashboard` action (after `index`, before `show`):

```ruby
  def index
    @projects = Project.includes(:project_type).all
  end

  def dashboard
    @project_types = ProjectType.all
    @statuses = Project.distinct.pluck(:status).compact
    @projects = Project.includes(:project_type, project_stages: :stage_template).all
    @projects = @projects.where(project_type_id: params[:project_type_id]) if params[:project_type_id].present?
    @projects = @projects.where(status: params[:status]) if params[:status].present?
  end

  def show
  end
```

- [ ] **Step 5: Write the view**

Create `app/views/projects/dashboard.html.erb`:

```erb
<h1>Gerencia — todos los proyectos</h1>

<%= form_with url: dashboard_projects_path, method: :get, local: true, class: "row g-2 mb-4" do |form| %>
  <div class="col-auto">
    <%= form.label :project_type_id, "Tipo", class: "form-label" %>
    <%= form.select :project_type_id, @project_types.collect { |pt| [pt.name, pt.id] },
          { include_blank: "Todos", selected: params[:project_type_id] }, class: "form-select" %>
  </div>
  <div class="col-auto">
    <%= form.label :status, "Estado", class: "form-label" %>
    <%= form.select :status, @statuses, { include_blank: "Todos", selected: params[:status] }, class: "form-select" %>
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
    dashboard_tasks = @projects.map do |project|
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
    dashboard_colors = @projects.map do |project|
      template_id = project.current_stage&.stage_template_id || "none"
      color = project.current_stage&.stage_template&.color || "#6c757d"
      [template_id, color]
    end.uniq
  %>
  <style>
    <% dashboard_colors.each do |template_id, color| %>
      .bar-wrapper.stage-color-<%= template_id %> .bar { fill: <%= color %>; }
    <% end %>
  </style>

  <div id="management-gantt" class="mb-4"></div>

  <script type="application/json" id="management-gantt-tasks"><%== dashboard_tasks.to_json %></script>

  <script src="https://cdn.jsdelivr.net/npm/frappe-gantt@0.6.1/dist/frappe-gantt.min.js"></script>
  <script>
    document.addEventListener("DOMContentLoaded", function () {
      var tasks = JSON.parse(document.getElementById("management-gantt-tasks").textContent);
      if (tasks.length > 0) {
        new Gantt("#management-gantt", tasks, {
          on_click: function (task) { window.location = task.edit_url; }
        });
      }
    });
  </script>
<% end %>
```

- [ ] **Step 6: Add the navbar link**

Edit `app/views/layouts/_navbar.html.erb`:

```erb
    <div class="navbar-nav me-auto">
      <%= link_to "Proyectos", projects_path, class: "nav-link" %>
      <%= link_to "Gerencia", dashboard_projects_path, class: "nav-link" %>
      <%= link_to "Administración", admin_project_types_path, class: "nav-link" %>
    </div>
```

(Only the new `link_to "Gerencia", ...` line is added, between the existing "Proyectos" and "Administración" links.)

- [ ] **Step 7: Run tests to verify they pass**

```bash
bin/rails test test/controllers/projects_controller_test.rb test/controllers/navbar_test.rb
```

Expected: PASS (14 runs in `projects_controller_test.rb` — 10 existing + 4 new — plus 2 runs in `navbar_test.rb` — 1 existing + 1 new — 0 failures).

- [ ] **Step 8: Run the full suite to confirm no regressions**

```bash
bin/rails test
```

Expected: all green (59 runs).

- [ ] **Step 9: Manual browser verification**

```bash
bin/rails server -p 3000 -d
```

Sign in, visit `/projects/dashboard`, confirm the filters work and the chart renders one bar per project. Click a bar, confirm it navigates to that project's `show` page. Stop the server:

```bash
kill $(cat tmp/pids/server.pid)
```

- [ ] **Step 10: Commit**

```bash
git add config/routes.rb app/controllers/projects_controller.rb app/views/projects/dashboard.html.erb \
  app/views/layouts/_navbar.html.erb test/controllers/projects_controller_test.rb test/controllers/navbar_test.rb
git commit -m "Add management dashboard: filterable multi-project Gantt"
```

---
