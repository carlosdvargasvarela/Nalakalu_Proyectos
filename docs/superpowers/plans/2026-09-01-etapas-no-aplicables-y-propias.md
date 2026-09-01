# Etapas no aplicables y etapas propias de un proyecto Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a project skip standard stages that don't apply to it (marked "no aplica", hidden but reactivatable, never lost) and add project-specific stages that aren't in the type's template — without corrupting the Gantt, progress calculations, or the "pendientes de fecha" panel, in either the per-project view or the general (one-bar-per-project) Gantt.

**Architecture:** One boolean column (`project_stages.not_applicable`) plus a small `applicable` scope. Every `Project` method that aggregates over `project_stages` gets a one-line exclusion, split by whether it runs on a preloaded association (in-memory `.reject`) or a fresh query (`.applicable` scope). A new, minimal `ProjectStagesController` (`create` for adding a custom stage, `update` for toggling `not_applicable`) — `update` is reached via a plain Turbo `link_to` (`data: { turbo_method: :patch }`), not a nested `<form>`, because the stage table is already one big form for the bulk date/progress editor and a nested form would be invalid HTML.

**Tech Stack:** Rails 7.2, Minitest + fixtures, Turbo (`turbo-rails`, already a dependency) for the No aplica/Reactivar links, native `<details>` for the collapsible section (no JS).

**Spec:** `docs/superpowers/specs/2026-09-01-etapas-no-aplicables-y-propias-design.md`

## Global Constraints

- Rails migration version must be `ActiveRecord::Migration[7.2]`.
- Wherever a `Project` method operates on an association that other call sites already preload via `.includes` (avoiding N+1 elsewhere in the app), exclude `not_applicable` stages with in-memory `.reject(&:not_applicable?)`, never the `.applicable` AR scope (which would issue a fresh query and defeat the preload). `.applicable` is reserved for call sites that already run a fresh query regardless (the Gantt's own stage query, `_stage_table.html.erb`, the new controller).
- No RSpec — Minitest + fixtures only, following this repo's existing test conventions (see `test/models/project_test.rb`, `test/models/project_stage_test.rb`).
- Reordering stages within a project, editing a stage's name once created, and letting restricted (progress-only) users mark/create stages are explicitly out of scope — do not add any of that.

---

### Task 1: `not_applicable` column and `ProjectStage.applicable` scope

**Files:**
- Create: `db/migrate/20260901090000_add_not_applicable_to_project_stages.rb`
- Modify: `app/models/project_stage.rb`
- Test: `test/models/project_stage_test.rb`

**Interfaces:**
- Produces: `project_stages.not_applicable` (boolean, `null: false`, default `false`); `ProjectStage.applicable` scope (`where(not_applicable: false)`).

- [ ] **Step 1: Write the migration**

```ruby
# db/migrate/20260901090000_add_not_applicable_to_project_stages.rb
class AddNotApplicableToProjectStages < ActiveRecord::Migration[7.2]
  def change
    add_column :project_stages, :not_applicable, :boolean, default: false, null: false
  end
end
```

- [ ] **Step 2: Run the migration**

Run: `bin/rails db:migrate`
Expected: `== 20260901090000 AddNotApplicableToProjectStages: migrated` and `db/schema.rb` gets the new column.

- [ ] **Step 3: Write the failing test**

Add to `test/models/project_stage_test.rb`:

```ruby
  test "not_applicable defaults to false" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    stage = project.project_stages.order(:id).first
    assert_equal false, stage.not_applicable
  end

  test "applicable scope excludes stages marked not_applicable" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    stage = project.project_stages.order(:id).first
    stage.update!(not_applicable: true)

    assert_not_includes project.project_stages.applicable, stage
    assert_includes project.project_stages, stage
  end
```

- [ ] **Step 4: Run test to verify it fails**

Run: `bin/rails test test/models/project_stage_test.rb -n "/not_applicable|applicable scope/"`
Expected: FAIL — `undefined method 'applicable'` (and `not_applicable` not yet a real column before the migration runs, but Step 2 already ran it — so this should only fail on the scope, not the column)

- [ ] **Step 5: Add the scope**

Modify `app/models/project_stage.rb` — add right after the `has_many` lines:

```ruby
  scope :applicable, -> { where(not_applicable: false) }
```

- [ ] **Step 6: Run test to verify it passes**

Run: `bin/rails test test/models/project_stage_test.rb`
Expected: PASS (9 runs, 0 failures — 7 pre-existing + 2 new)

- [ ] **Step 7: Commit**

```bash
git add db/migrate/20260901090000_add_not_applicable_to_project_stages.rb db/schema.rb app/models/project_stage.rb test/models/project_stage_test.rb
git commit -m "Agregar columna not_applicable y scope applicable a ProjectStage"
```

---

### Task 2: Exclude not-applicable stages from every `Project` aggregate

**Files:**
- Modify: `app/models/project.rb`
- Test: `test/models/project_test.rb`

**Interfaces:**
- Consumes: `ProjectStage#not_applicable` (Task 1).
- Produces: `Project#find_stage` becomes public (was private) and excludes not-applicable stages by name — later consumed by Task 5's view fix. `start_date`, `end_date`, `gantt_window`, `stages_missing_dates`, `current_stage`, `progress_percent`, `progress_status`, `overdue?`, `apply_auto_duration!`, `pending_auto_duration_start_date?` all exclude not-applicable stages (the last four already inherit correctness once `find_stage`/`start_date`/`end_date` are fixed, or need a one-line addition — see below).

- [ ] **Step 1: Write the failing tests**

Add to `test/models/project_test.rb` (near the existing `start_date`/`end_date`/`current_stage`/`progress_status`/`stages_missing_dates`/`apply_auto_duration!`/`pending_auto_duration_start_date?` tests — match their existing style: `Project.create!` + `project.project_stages.order(:id)`/`find_by`):

```ruby
  test "start_date and end_date ignore a stage marked not_applicable" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    stages = project.project_stages.order(:id).to_a
    stages[0].update!(start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 1, 10))
    stages[1].update!(start_date: Date.new(2026, 6, 1), end_date: Date.new(2026, 6, 10), not_applicable: true)

    assert_equal Date.new(2026, 1, 1), project.start_date
    assert_equal Date.new(2026, 1, 10), project.end_date
  end

  test "stages_missing_dates ignores a stage marked not_applicable" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    stage = project.project_stages.order(:id).first
    stage.update!(not_applicable: true)

    assert_not_includes project.stages_missing_dates, stage
  end

  test "current_stage ignores a stage marked not_applicable" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    stages = project.project_stages.order(:id).to_a
    stages.last.update!(progress_percent: 50, not_applicable: true)

    assert_equal stages.first, project.current_stage
  end

  test "progress_percent and progress_status ignore a stage marked not_applicable" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    stages = project.project_stages.order(:id).to_a
    stages.each { |s| s.update!(progress_percent: 100) }
    stages.last.update!(progress_percent: 0, not_applicable: true)

    assert_equal 100, project.progress_percent
    assert_equal "finalizado", project.progress_status
  end

  test "find_stage ignores a stage with a matching name marked not_applicable" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    stage = project.project_stages.order(:id).first
    stage.update!(not_applicable: true)

    assert_nil project.find_stage(stage.name)
  end

  test "apply_auto_duration! skips a stage marked not_applicable" do
    field = FieldDefinition.create!(project_type: @project_type, key: "cantidad", label: "Cantidad", data_type: "number", position: 10)
    @project_type.update!(auto_stage_duration_enabled: true, duration_reference_field_definition: field)
    diseno = stage_templates(:diseno_aprobacion)
    revision = stage_templates(:revision_inicial)
    DurationProfile.create!(
      project_type: @project_type, operator: "between", min_value: 100, max_value: 500,
      durations: { diseno.id.to_s => 5, revision.id.to_s => 3 }
    )
    project = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: { "cantidad" => "300" })
    diseno_stage = project.project_stages.find_by(stage_template: diseno)
    diseno_stage.update!(not_applicable: true)

    assert project.apply_auto_duration!(Date.new(2026, 1, 1))

    assert_nil diseno_stage.reload.start_date
  end

  test "pending_auto_duration_start_date? is false when the first stage is marked not_applicable" do
    field = FieldDefinition.create!(project_type: @project_type, key: "cantidad", label: "Cantidad", data_type: "number", position: 10)
    @project_type.update!(auto_stage_duration_enabled: true, duration_reference_field_definition: field)
    project = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: {})
    first_template = project.project_type.stage_templates.min_by(&:position)
    project.project_stages.find_by(stage_template_id: first_template.id).update!(not_applicable: true)

    assert_not project.pending_auto_duration_start_date?
  end
```

These two tests mirror the exact setup already used by this file's existing `"apply_auto_duration! sets sequential dates per stage_template when a profile matches"` and `"pending_auto_duration_start_date? is true when the first stage_template's stage has no start_date"` tests (both build auto-duration configuration dynamically from `@project_type` — set in this file's `setup` block to `project_types(:instalaciones)` — rather than from a dedicated fixture; there is no separate "auto duration" project type fixture in this repo). Do not introduce new fixtures — follow the same inline `FieldDefinition`/`DurationProfile` construction those tests already use.

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/models/project_test.rb -n "/not_applicable/"`
Expected: FAIL — `find_stage` is private (`NoMethodError: private method`), and the aggregate methods don't yet exclude not-applicable stages.

- [ ] **Step 3: Make the changes**

Modify `app/models/project.rb`:

```ruby
  def start_date
    project_stages.reject(&:not_applicable?).map(&:start_date).compact.min
  end

  def end_date
    project_stages.reject(&:not_applicable?).map(&:end_date).compact.max
  end

  def stages_missing_dates
    project_stages.reject(&:not_applicable?).select(&:dates_missing?)
  end
```

(replacing the existing `start_date`/`end_date`/`stages_missing_dates` bodies one-for-one.)

Move `find_stage` from the `private` section to public, right after `progress_status` and before `overdue?`, and add the not-applicable exclusion:

```ruby
  def find_stage(stage_name)
    return nil if stage_name.blank?
    project_stages.find { |stage| stage.name == stage_name && !stage.not_applicable? }
  end
```

(delete the old private `find_stage` definition — don't leave two.)

Update `current_stage`:

```ruby
  def current_stage
    applicable_stages = project_stages.reject(&:not_applicable?)
    applicable_stages.select { |stage| stage.progress_percent > 0 }.max_by(&:id) || applicable_stages.min_by(&:id)
  end
```

Update `progress_percent`:

```ruby
  def progress_percent(stage_name: nil)
    stage = find_stage(stage_name)
    return stage.progress_percent if stage

    values = project_stages.reject(&:not_applicable?).map(&:progress_percent)
    values.any? ? (values.sum / values.size.to_f).round : 0
  end
```

Update `progress_status`:

```ruby
  def progress_status(stage_name: nil)
    stage = find_stage(stage_name)
    return stage.progress_status if stage

    applicable_stages = project_stages.reject(&:not_applicable?)
    return "sin_iniciar" if applicable_stages.all? { |stage| stage.progress_percent.zero? }
    return "finalizado" if applicable_stages.all? { |stage| stage.progress_percent == 100 }
    "iniciado"
  end
```

Update `apply_auto_duration!` — add one line right after the existing `next unless stage`:

```ruby
      stage = project_stages.find_by(stage_template_id: template.id)
      next unless stage
      next if stage.not_applicable?
      stage_end = cursor + (days.to_i - 1).days
```

Update `pending_auto_duration_start_date?`:

```ruby
  def pending_auto_duration_start_date?
    return false unless project_type.auto_stage_duration_enabled?
    first_template = project_type.stage_templates.min_by(&:position)
    return false unless first_template
    stage = project_stages.find { |s| s.stage_template_id == first_template.id }
    stage.present? && !stage.not_applicable? && stage.start_date.blank?
  end
```

`gantt_window` and `overdue?` need no direct changes — both already derive entirely from `start_date`/`end_date`/`progress_status`, which are now fixed.

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/models/project_test.rb`
Expected: PASS, 0 failures (all pre-existing project_test.rb tests plus the new ones)

- [ ] **Step 5: Commit**

```bash
git add app/models/project.rb test/models/project_test.rb
git commit -m "Excluir etapas no aplicables de los cálculos agregados de Project"
```

---

### Task 3: `ProjectStagesController` (create custom stage, toggle not_applicable)

**Files:**
- Create: `app/controllers/project_stages_controller.rb`
- Modify: `config/routes.rb`
- Test: `test/controllers/project_stages_controller_test.rb`

**Interfaces:**
- Consumes: `ProjectStage` (Task 1), `current_user.can_edit_project?(project)` (existing, used by `EventsController`/`ProjectResponsiblesController`).
- Produces: routes `project_project_stages_path(project)` (POST create), `project_project_stage_path(project, stage)` (PATCH update) — the `update` route is reached only via `link_to ..., data: { turbo_method: :patch }` in Task 4's views, never a `<form>`.

- [ ] **Step 1: Add routes**

Modify `config/routes.rb` — inside `resources :projects do ... end`, add next to `resources :events`:

```ruby
    resources :project_stages, only: [:create, :update]
```

- [ ] **Step 2: Write the failing controller test**

```ruby
# test/controllers/project_stages_controller_test.rb
require "test_helper"

class ProjectStagesControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:juan) }
  setup do
    @project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
  end

  test "create adds a project-specific stage with no stage_template" do
    assert_difference("@project.project_stages.count", 1) do
      post project_project_stages_path(@project), params: {
        project_stage: { name: "Etapa propia", start_date: "2026-01-01", end_date: "2026-01-10" }
      }
    end
    assert_redirected_to project_path(@project)
    stage = @project.project_stages.order(:id).last
    assert_equal "Etapa propia", stage.name
    assert_nil stage.stage_template_id
  end

  test "create with a blank name redirects with an error" do
    assert_no_difference("@project.project_stages.count") do
      post project_project_stages_path(@project), params: { project_stage: { name: "" } }
    end
    assert_redirected_to project_path(@project)
  end

  test "update marks a stage not_applicable" do
    stage = @project.project_stages.first
    patch project_project_stage_path(@project, stage), params: { project_stage: { not_applicable: true } }
    assert stage.reload.not_applicable?
  end

  test "update reactivates a stage" do
    stage = @project.project_stages.first
    stage.update!(not_applicable: true)
    patch project_project_stage_path(@project, stage), params: { project_stage: { not_applicable: false } }
    assert_not stage.reload.not_applicable?
  end

  test "update ignores an attempt to change fields other than not_applicable" do
    stage = @project.project_stages.first
    original_name = stage.name
    patch project_project_stage_path(@project, stage), params: {
      project_stage: { not_applicable: true, name: "Nombre hackeado" }
    }
    stage.reload
    assert stage.not_applicable?
    assert_equal original_name, stage.name
  end

  test "create is blocked for a visor without edit access" do
    sign_in users(:maria)
    assert_no_difference("@project.project_stages.count") do
      post project_project_stages_path(@project), params: { project_stage: { name: "Intento" } }
    end
    assert_redirected_to project_path(@project)
  end

  test "update is blocked for a visor without edit access" do
    stage = @project.project_stages.first
    sign_in users(:maria)
    patch project_project_stage_path(@project, stage), params: { project_stage: { not_applicable: true } }
    assert_not stage.reload.not_applicable?
  end
end
```

- [ ] **Step 3: Run test to verify it fails**

Run: `bin/rails test test/controllers/project_stages_controller_test.rb`
Expected: FAIL — routing error / uninitialized constant `ProjectStagesController`

- [ ] **Step 4: Write the controller**

```ruby
# app/controllers/project_stages_controller.rb
class ProjectStagesController < ApplicationController
  before_action :set_project
  before_action :authorize_edit!
  before_action :set_project_stage, only: [:update]

  def create
    @project_stage = @project.project_stages.new(project_stage_params)
    if @project_stage.save
      redirect_to project_path(@project)
    else
      redirect_to project_path(@project), alert: @project_stage.errors.full_messages.to_sentence
    end
  end

  def update
    @project_stage.update(not_applicable_param)
    redirect_to project_path(@project)
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end

  def set_project_stage
    @project_stage = @project.project_stages.find(params[:id])
  end

  def authorize_edit!
    return if current_user.can_edit_project?(@project)
    redirect_to project_path(@project), alert: "No tenés permiso para hacer eso."
  end

  def project_stage_params
    params.require(:project_stage).permit(:name, :start_date, :end_date)
  end

  def not_applicable_param
    params.require(:project_stage).permit(:not_applicable)
  end
end
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bin/rails test test/controllers/project_stages_controller_test.rb`
Expected: PASS (7 runs, 0 failures)

- [ ] **Step 6: Commit**

```bash
git add config/routes.rb app/controllers/project_stages_controller.rb test/controllers/project_stages_controller_test.rb
git commit -m "Agregar ProjectStagesController para crear etapas propias y marcar no aplicable"
```

---

### Task 4: UI — "+ Etapa", "No aplica" / "Reactivar", collapsible section

**Files:**
- Modify: `app/views/projects/_stage_table.html.erb`
- Modify: `app/views/projects/_stage_table_restricted.html.erb`
- Modify: `test/controllers/projects_controller_test.rb`

**Interfaces:**
- Consumes: `ProjectStage.applicable` scope (Task 1), `project_project_stages_path`/`project_project_stage_path` (Task 3).

- [ ] **Step 1: Write the failing tests**

Add to `test/controllers/projects_controller_test.rb` (this file already has many `show` tests for the stage table — match their style, e.g. `test "show renders an editable table row for each stage"`):

```ruby
  test "show renders a + Etapa button and a form to add a project-specific stage" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_path(project)
    assert_response :success
    assert_select "button", text: /Etapa/
    assert_select "form[action=?]", project_project_stages_path(project)
  end

  test "show hides a stage marked not_applicable from the main stage table" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    stage = project.project_stages.order(:id).first
    stage.update!(not_applicable: true)

    get project_path(project)
    assert_response :success
    assert_select "#stage-table-#{project.id} tr##{"stage-#{stage.id}"}", count: 0
  end

  test "show lists a not_applicable stage in the collapsible section with a Reactivar link" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    stage = project.project_stages.order(:id).first
    stage.update!(not_applicable: true)

    get project_path(project)
    assert_response :success
    assert_select "details summary", text: /no aplicables \(1\)/
    assert_select "a[href=?][data-turbo-method=?]", project_project_stage_path(project, stage), "patch"
  end

  test "show renders a No aplica link for each applicable stage" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    stage = project.project_stages.order(:id).first

    get project_path(project)
    assert_response :success
    assert_select "a[href=?][data-turbo-method=?]", project_project_stage_path(project, stage), "patch"
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n "/Etapa|not_applicable/"`
Expected: FAIL — none of this markup exists yet.

- [ ] **Step 3: Rewrite `_stage_table.html.erb`**

Replace the whole file:

```erb
<%= link_to "+ Etapa", "#add-stage-modal", class: "btn btn-outline-primary btn-sm mb-2", data: { bs_toggle: "modal" } %>

<%= form_with model: project do |f| %>
  <table id="stage-table-<%= project.id %>" class="table table-sm table-bordered mb-0 stage-table" data-controller="stage-table">
    <thead>
      <tr><th>Etapa</th><th>Inicio</th><th>Fin</th><th>Duración (días)</th><th>% Avance</th><th>Estado</th><th></th></tr>
    </thead>
    <tbody>
      <%= f.fields_for :project_stages, project.project_stages.applicable.includes(:stage_template).order(:id) do |sf| %>
        <tr id="stage-<%= sf.object.id %>">
          <td><%= sf.object.name %></td>
          <td><%= sf.hidden_field :id %><%= sf.date_field :start_date, class: "form-control form-control-sm fecha-input" %></td>
          <td><%= sf.date_field :end_date, class: "form-control form-control-sm fecha-input" %></td>
          <td><input type="number" min="1" class="form-control form-control-sm duracion-input" data-action="input->stage-table#syncEndDate"></td>
          <td><%= sf.number_field :progress_percent, min: 0, max: 100, class: "form-control form-control-sm avance-input" %></td>
          <td>
            <%= progress_status_badge(sf.object.progress_status) %>
            <%= overdue_badge if sf.object.overdue? %>
          </td>
          <td>
            <%= link_to "No aplica", project_project_stage_path(project, sf.object),
                  data: { turbo_method: :patch, turbo_confirm: "¿Marcar \"#{sf.object.name}\" como no aplicable a este proyecto?" },
                  class: "btn btn-outline-secondary btn-sm" %>
          </td>
        </tr>
      <% end %>
    </tbody>
  </table>
  <%= f.submit "Guardar cambios", class: "btn btn-primary btn-sm mt-3" %>
<% end %>

<%
  not_applicable_stages = project.project_stages.where(not_applicable: true).order(:id)
%>
<% if not_applicable_stages.any? %>
  <details class="mt-3">
    <summary class="text-muted">Etapas no aplicables (<%= not_applicable_stages.size %>)</summary>
    <ul class="list-group list-group-flush mt-2">
      <% not_applicable_stages.each do |stage| %>
        <li class="list-group-item d-flex justify-content-between align-items-center">
          <span><%= stage.name %></span>
          <%= link_to "Reactivar", project_project_stage_path(project, stage),
                data: { turbo_method: :patch, "project_stage[not_applicable]": false },
                class: "btn btn-outline-primary btn-sm" %>
        </li>
      <% end %>
    </ul>
  </details>
<% end %>

<div class="modal fade" id="add-stage-modal" tabindex="-1">
  <div class="modal-dialog">
    <div class="modal-content">
      <%= form_with model: ProjectStage.new, url: project_project_stages_path(project) do |form| %>
        <div class="modal-header">
          <h5 class="modal-title">Agregar etapa</h5>
          <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
        </div>
        <div class="modal-body">
          <% if form.object.errors.any? %>
            <div class="alert alert-danger">
              <ul class="mb-0">
                <% form.object.errors.full_messages.each do |message| %>
                  <li><%= message %></li>
                <% end %>
              </ul>
            </div>
          <% end %>
          <div class="mb-3">
            <%= form.label :name, "Nombre", class: "form-label" %>
            <%= form.text_field :name, class: "form-control" %>
          </div>
          <div class="row g-2">
            <div class="col">
              <%= form.label :start_date, "Fecha de inicio", class: "form-label" %>
              <%= form.date_field :start_date, class: "form-control" %>
            </div>
            <div class="col">
              <%= form.label :end_date, "Fecha de fin", class: "form-label" %>
              <%= form.date_field :end_date, class: "form-control" %>
            </div>
          </div>
        </div>
        <div class="modal-footer">
          <button type="button" class="btn btn-outline-secondary" data-bs-dismiss="modal">Cancelar</button>
          <%= form.submit "Agregar", class: "btn btn-primary" %>
        </div>
      <% end %>
    </div>
  </div>
</div>
```

**Important — verify the Turbo attribute name before running tests:** the "Reactivar" link above passes `"project_stage[not_applicable]": false` as a `data:` key so Rails' `link_to` renders it as `data-project_stage[not_applicable]="false"`. Confirm whether this repo's Turbo/Rails version actually reads a bracketed `data-*` attribute as a nested param on a `link_to` PATCH the way a `form_with` would — if it does not (some Turbo versions only send bracket-named data attributes verbatim as a flat key, not nested params), instead give `ProjectStagesController#update` two distinct actions is overkill; simplest fix is to add `not_applicable: false` as a query string on the href instead: `project_project_stage_path(project, stage, project_stage: { not_applicable: false })`, which Rails' `params.require(:project_stage).permit(:not_applicable)` reads identically regardless of Turbo's data-attribute handling, since it arrives as a normal query param on the PATCH request. Prefer the query-string form for the "Reactivar" link if there's any doubt; use it for the "No aplica" link too if you switch (there, the query string would be `project_stage: { not_applicable: true }` — but there `turbo_confirm` is also needed, so keep `data: { turbo_method: :patch, turbo_confirm: "..." }` and add the query params directly via `project_project_stage_path(project, stage, project_stage: { not_applicable: true })`). Whichever approach you use, verify by actually running the test in Step 5 below, not by reading the Turbo docs — the test will tell you unambiguously whether the param arrived.

- [ ] **Step 4: Update `_stage_table_restricted.html.erb`**

Modify the one line that queries stages:

```erb
      <% project.project_stages.applicable.includes(:stage_template).order(:id).each do |stage| %>
```

(replacing `project.project_stages.includes(:stage_template).order(:id).each do |stage|`)

- [ ] **Step 5: Run tests to verify they pass**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n "/Etapa|not_applicable/"`
Expected: PASS (4 runs, 0 failures) — if the Turbo data-attribute question from Step 3 came up, this run is what resolves it.

- [ ] **Step 6: Run the full projects controller test file to check for regressions**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: PASS, same failure count as before this task (0 new failures) — pay particular attention to any existing test asserting the exact column count or structure of `_stage_table.html.erb`'s `<table>` (a new trailing `<th></th>`/`<td>` column was added).

- [ ] **Step 7: Commit**

```bash
git add app/views/projects/_stage_table.html.erb app/views/projects/_stage_table_restricted.html.erb test/controllers/projects_controller_test.rb
git commit -m "Agregar UI para etapas propias y marcar/reactivar etapas no aplicables"
```

---

### Task 5: Fix the general (one-bar-per-project) Gantt and its stage filter

**Files:**
- Modify: `app/views/projects/_project_type_section.html.erb`
- Modify: `app/views/projects/show.html.erb`
- Modify: `test/controllers/projects_controller_test.rb`

**Interfaces:**
- Consumes: `Project#find_stage` (now public, Task 2), `ProjectStage.applicable` (Task 1).

- [ ] **Step 1: Write the failing tests**

Add to `test/controllers/projects_controller_test.rb`:

```ruby
  test "index's Gantt filtered by a stage that's not_applicable on a project omits that project" do
    project_type = project_types(:instalaciones)
    project = Project.create!(project_type: project_type, name: "Torre Norte", custom_fields: {})
    stage = project.project_stages.find_by(name: "Producción")
    stage.update!(start_date: Date.current, end_date: Date.current + 5.days, not_applicable: true)

    get project_type_projects_path(project_type.slug, stage_name: "Producción")
    assert_response :success
    assert_select "body", { text: /Torre Norte/, count: 0 }
  end

  test "index's Gantt (no stage filter) date range ignores a not_applicable stage's dates" do
    project_type = project_types(:instalaciones)
    project = Project.create!(project_type: project_type, name: "Torre Norte", custom_fields: {})
    stages = project.project_stages.order(:id).to_a
    stages[0].update!(start_date: Date.new(2026, 3, 1), end_date: Date.new(2026, 3, 10))
    stages[1].update!(start_date: Date.new(2026, 9, 1), end_date: Date.new(2026, 9, 10), not_applicable: true)

    get project_type_projects_path(project_type.slug)
    assert_response :success
    tasks = json_data_attribute('[data-controller="gantt-project-list"]', "data-gantt-project-list-tasks-value")
    task = tasks.find { |t| t["id"] == project.id.to_s }
    assert_equal "2026-03-10", task["end"]
  end
```

This reuses the `json_data_attribute(selector, attribute)` private helper already defined near the bottom of this test file (Nokogiri-based; used by the existing `"index shows one Gantt task per project by default"` test) — do not reimplement JSON parsing inline, and do not redefine the helper.

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n "/not_applicable/"`
Expected: FAIL — the not_applicable stage still counts in both the filter match and the date range.

- [ ] **Step 3: Fix `_project_type_section.html.erb`**

Replace both occurrences of:
```erb
stage = project.project_stages.find { |s| s.name == section[:stage_name] }
```
(one inside the `gantt_tasks = projects_list.filter_map do |project| ... end` block, one inside the `pending_projects = projects_list.filter_map do |project| ... end` block)

with:
```erb
stage = project.find_stage(section[:stage_name])
```

Then, in the `gantt_tasks` block's `else` branch (the one with no `section[:stage_name]`), change:
```erb
next if (project_type.require_stage_dates? || project_type.auto_stage_duration_enabled?) && project.project_stages.all?(&:dates_missing?)
```
to:
```erb
next if (project_type.require_stage_dates? || project_type.auto_stage_duration_enabled?) && project.project_stages.reject(&:not_applicable?).all?(&:dates_missing?)
```

- [ ] **Step 4: Check `show.html.erb`'s Gantt block for the same gap**

Read the `stages = @project.project_stages.includes(:stage_template).order(:id)` line in `app/views/projects/show.html.erb` (already changed in Task 4? — no, Task 4 only touched `_stage_table.html.erb`/`_stage_table_restricted.html.erb`, not `show.html.erb`'s own Gantt-building block). Change it to:
```erb
  stages = @project.project_stages.applicable.includes(:stage_template).order(:id)
```
This is a fresh query in this view (not a preloaded association reused elsewhere), so `.applicable` is correct here per the Global Constraints rule.

- [ ] **Step 5: Run tests to verify they pass**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n "/not_applicable/"`
Expected: PASS (2 runs, 0 failures)

- [ ] **Step 6: Run the full test suite**

Run: `bin/rails test`
Expected: PASS, 0 new failures beyond this repo's existing pre-existing baseline (unrelated Navbar/Authentication/fixture-order failures — check the count matches what existed before this branch by running `git stash` + the same command if there's any doubt about which failures are pre-existing).

- [ ] **Step 7: Commit**

```bash
git add app/views/projects/_project_type_section.html.erb app/views/projects/show.html.erb test/controllers/projects_controller_test.rb
git commit -m "Excluir etapas no aplicables del Gantt general y su filtro por etapa"
```

---

## Self-Review Notes

- **Spec coverage:** `not_applicable` column + scope (Task 1); every `Project` aggregate method (Task 2); custom-stage creation + not_applicable toggle via a non-nested-form Turbo link (Task 3); "+ Etapa" button, "No aplica" links, collapsible reactivation section, restricted-view filtering (Task 4); the general Gantt and its stage filter — explicitly called out by the user as the thing to get right (Task 5). All spec sections covered.
- **The nested-`<form>` HTML problem is real and was caught before writing code**, not after — Task 4's `_stage_table.html.erb` uses `link_to` with `data: { turbo_method: :patch }` for both No aplica and Reactivar, never a `form_with` nested inside the bulk-edit form.
- **Type/name consistency:** `Project#find_stage` (Task 2, made public) is consumed by both `progress_percent`/`progress_status` internally and by `_project_type_section.html.erb` (Task 5) — same method, one definition. `ProjectStage.applicable` (Task 1) is used identically in Task 4 (`_stage_table.html.erb`, `_stage_table_restricted.html.erb`) and Task 5 (`show.html.erb`).
- **No placeholders**, except two explicitly-flagged spots where the plan tells the implementer to verify a concrete detail against this repo's actual code/behavior before trusting the snippet verbatim (Task 2's fixture names for the auto-duration tests; Task 4's Turbo data-attribute nesting behavior) — both are called out with exactly what to check and how, not left vague.
