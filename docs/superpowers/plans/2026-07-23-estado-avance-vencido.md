# Estado de avance y "Vencido" — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a progress-based status (Sin iniciar/Iniciado/Finalizado) to both `Project` and `ProjectStage`, plus an independent "Vencido" (overdue) flag when a date has passed without reaching 100%, and surface both as badges everywhere the project/stage already shows its lifecycle status.

**Architecture:** Two model methods per class (`progress_status`, `overdue?`) computed from existing columns (`progress_percent`, `end_date`) — no migration. Two new helper methods (`progress_status_badge`, `overdue_badge`) reusing the existing `status_badge` pattern. Three view touch points: the project detail header, the Seguimiento per-project band, and the shared `_stage_table` partial (which automatically covers both pages).

**Tech Stack:** Ruby on Rails, Minitest + fixtures.

## Global Constraints

- No new database columns/migrations — both new states are purely derived from data that already exists.
- Neither model method is named `status` — `Project` already has a `status` column (active/archived); a same-named method would shadow/collide with it. Both models use `progress_status` instead.
- "Vencido" never applies when there's no end date — `overdue?` is `false` if `end_date` is `nil`, regardless of progress.
- The new badges are shown *alongside* the existing `status_badge`/`Editar`/etc. — nothing existing is removed or replaced.

---

### Task 1: Model methods

**Files:**
- Modify: `app/models/project_stage.rb`
- Modify: `app/models/project.rb`
- Modify: `test/models/project_stage_test.rb`
- Modify: `test/models/project_test.rb`

**Interfaces:**
- Consumes: `ProjectStage#progress_percent`/`#end_date` (unchanged columns), `Project#project_stages`/`#end_date` (unchanged).
- Produces: `ProjectStage#progress_status` → `"sin_iniciar" | "iniciado" | "finalizado"`, `ProjectStage#overdue?` → boolean, `Project#progress_status` → same three values, `Project#overdue?` → boolean. Consumed by Task 2's helper/view work.

- [ ] **Step 1: Write the failing tests for `ProjectStage`**

Add to `test/models/project_stage_test.rb`, inside the existing test class (check the file first for its current `setup`/fixture conventions before inserting — it should already have a way to build a `ProjectStage`, e.g. via a `Project` fixture or `Project.create!`):

```ruby
  test "progress_status is sin_iniciar at 0%, iniciado between, finalizado at 100%" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    stage = project.project_stages.order(:id).first

    stage.update!(progress_percent: 0)
    assert_equal "sin_iniciar", stage.progress_status

    stage.update!(progress_percent: 45)
    assert_equal "iniciado", stage.progress_status

    stage.update!(progress_percent: 100)
    assert_equal "finalizado", stage.progress_status
  end

  test "overdue? is true only with a past end_date and progress under 100%" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    stage = project.project_stages.order(:id).first

    stage.update!(end_date: Date.current - 1.day, progress_percent: 50)
    assert stage.overdue?

    stage.update!(end_date: Date.current - 1.day, progress_percent: 100)
    assert_not stage.overdue?

    stage.update!(end_date: nil, progress_percent: 50)
    assert_not stage.overdue?

    stage.update!(end_date: Date.current + 1.day, progress_percent: 50)
    assert_not stage.overdue?
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/models/project_stage_test.rb`
Expected: FAIL — `NoMethodError: undefined method 'progress_status'`/`'overdue?'`.

- [ ] **Step 3: Implement `ProjectStage#progress_status`/`#overdue?`**

Edit `app/models/project_stage.rb`:

```ruby
class ProjectStage < ApplicationRecord
  belongs_to :project
  belongs_to :stage_template, optional: true
  belongs_to :user, optional: true

  validates :name, presence: true
  validates :progress_percent, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }

  def progress_status
    return "finalizado" if progress_percent == 100
    return "sin_iniciar" if progress_percent.zero?
    "iniciado"
  end

  def overdue?
    end_date.present? && end_date < Date.current && progress_percent < 100
  end
end
```

- [ ] **Step 4: Run the `ProjectStage` tests to verify they pass**

Run: `bin/rails test test/models/project_stage_test.rb`
Expected: PASS (all tests)

- [ ] **Step 5: Write the failing tests for `Project`**

Add to `test/models/project_test.rb`, inside the existing test class:

```ruby
  test "progress_status is sin_iniciar when every stage is at 0%" do
    project = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: {})
    assert_equal "sin_iniciar", project.progress_status
  end

  test "progress_status is iniciado when at least one stage has progress but not all are finished" do
    project = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: {})
    project.project_stages.order(:id).first.update!(progress_percent: 40)
    assert_equal "iniciado", project.reload.progress_status
  end

  test "progress_status is finalizado when every stage is at 100%" do
    project = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: {})
    project.project_stages.each { |stage| stage.update!(progress_percent: 100) }
    assert_equal "finalizado", project.reload.progress_status
  end

  test "project overdue? is true only when its end_date has passed and it isn't finalizado" do
    project = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: {})
    stages = project.project_stages.order(:id).to_a
    stages[0].update!(end_date: Date.current - 1.day, progress_percent: 50)

    assert project.reload.overdue?

    stages.each { |stage| stage.update!(progress_percent: 100) }
    assert_not project.reload.overdue?
  end

  test "project overdue? is false when it has no end_date yet" do
    project = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: {})
    assert_nil project.end_date
    assert_not project.overdue?
  end
```

- [ ] **Step 6: Run the tests to verify they fail**

Run: `bin/rails test test/models/project_test.rb`
Expected: FAIL — `NoMethodError: undefined method 'progress_status'`/`'overdue?'`.

- [ ] **Step 7: Implement `Project#progress_status`/`#overdue?`**

Edit `app/models/project.rb` — add after `installer`:

```ruby
  def progress_status
    return "sin_iniciar" if project_stages.all? { |stage| stage.progress_percent.zero? }
    return "finalizado" if project_stages.all? { |stage| stage.progress_percent == 100 }
    "iniciado"
  end

  def overdue?
    end_date.present? && end_date < Date.current && progress_status != "finalizado"
  end
```

- [ ] **Step 8: Run the tests to verify they pass**

Run: `bin/rails test test/models/project_test.rb`
Expected: PASS (all tests)

- [ ] **Step 9: Run the full suite**

Run: `bin/rails test`
Expected: PASS

- [ ] **Step 10: Commit**

```bash
git add app/models/project_stage.rb app/models/project.rb test/models/project_stage_test.rb test/models/project_test.rb
git commit -m "Add progress_status (Sin iniciar/Iniciado/Finalizado) and overdue? to Project and ProjectStage"
```

---

### Task 2: Badges in the views

**Files:**
- Modify: `app/helpers/application_helper.rb`
- Modify: `app/views/projects/show.html.erb`
- Modify: `app/views/projects/tracker.html.erb`
- Modify: `app/views/projects/_stage_table.html.erb`
- Modify: `test/helpers/application_helper_test.rb`
- Modify: `test/controllers/projects_controller_test.rb`

**Interfaces:**
- Consumes: `Project#progress_status`/`#overdue?`, `ProjectStage#progress_status`/`#overdue?` (Task 1, already committed).
- Produces: `ApplicationHelper#progress_status_badge(progress_status)`, `ApplicationHelper#overdue_badge` — no later task in this plan depends on them, this is the last task.

- [ ] **Step 1: Write the failing helper tests**

Add to `test/helpers/application_helper_test.rb`, inside the existing test class:

```ruby
  test "progress_status_badge renders the right label and color for each state" do
    assert_match(/badge bg-secondary/, progress_status_badge("sin_iniciar"))
    assert_match(/Sin iniciar/, progress_status_badge("sin_iniciar"))
    assert_match(/badge bg-info/, progress_status_badge("iniciado"))
    assert_match(/Iniciado/, progress_status_badge("iniciado"))
    assert_match(/badge bg-success/, progress_status_badge("finalizado"))
    assert_match(/Finalizado/, progress_status_badge("finalizado"))
  end

  test "overdue_badge renders a red Vencido badge" do
    assert_match(/badge bg-danger/, overdue_badge)
    assert_match(/Vencido/, overdue_badge)
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/helpers/application_helper_test.rb`
Expected: FAIL — `NoMethodError: undefined method 'progress_status_badge'`/`'overdue_badge'`.

- [ ] **Step 3: Implement the helper methods**

Edit `app/helpers/application_helper.rb`:

```ruby
module ApplicationHelper
  STATUS_LABELS = { "active" => "Activo", "archived" => "Archivado" }.freeze
  STATUS_BADGE_CLASSES = { "active" => "bg-success", "archived" => "bg-secondary" }.freeze
  PROGRESS_STATUS_LABELS = { "sin_iniciar" => "Sin iniciar", "iniciado" => "Iniciado", "finalizado" => "Finalizado" }.freeze
  PROGRESS_STATUS_BADGE_CLASSES = { "sin_iniciar" => "bg-secondary", "iniciado" => "bg-info text-dark", "finalizado" => "bg-success" }.freeze

  def status_label(status)
    STATUS_LABELS.fetch(status, status)
  end

  def status_badge(status)
    tag.span(status_label(status), class: "badge #{STATUS_BADGE_CLASSES.fetch(status, 'bg-light text-dark')}")
  end

  def progress_status_label(progress_status)
    PROGRESS_STATUS_LABELS.fetch(progress_status, progress_status)
  end

  def progress_status_badge(progress_status)
    tag.span(progress_status_label(progress_status), class: "badge #{PROGRESS_STATUS_BADGE_CLASSES.fetch(progress_status, 'bg-light text-dark')}")
  end

  def overdue_badge
    tag.span("Vencido", class: "badge bg-danger")
  end
end
```

- [ ] **Step 4: Run the helper tests to verify they pass**

Run: `bin/rails test test/helpers/application_helper_test.rb`
Expected: PASS (all tests)

- [ ] **Step 5: Write the failing controller tests**

Add to `test/controllers/projects_controller_test.rb`, inside the existing test class:

```ruby
  test "show displays the project's progress status and overdue badges" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    project.project_stages.order(:id).first.update!(end_date: Date.current - 1.day, progress_percent: 40)

    get project_path(project)
    assert_response :success
    assert_select "span.badge.bg-info", "Iniciado"
    assert_select "span.badge.bg-danger", "Vencido"
  end

  test "tracker displays each project's progress status badge" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get tracker_projects_path
    assert_response :success
    assert_select "span.badge.bg-secondary", "Sin iniciar"
  end

  test "the stage table shows each stage's progress status and overdue badges" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    stage = project.project_stages.order(:id).first
    stage.update!(end_date: Date.current - 1.day, progress_percent: 40)

    get project_path(project)
    assert_response :success
    assert_select "#stage-#{stage.id} span.badge.bg-info", "Iniciado"
    assert_select "#stage-#{stage.id} span.badge.bg-danger", "Vencido"
  end
```

- [ ] **Step 6: Run the tests to verify they fail**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: FAIL — no progress-status/overdue badges rendered anywhere yet.

- [ ] **Step 7: Add the badges to `show.html.erb`'s header**

Edit `app/views/projects/show.html.erb` — replace:

```erb
    <h1 class="d-inline-block me-2 mb-0"><%= @project.name %></h1>
    <%= status_badge(@project.status) %>
    <p class="text-muted mb-0">Tipo: <%= @project.project_type.name %></p>
```

with:

```erb
    <h1 class="d-inline-block me-2 mb-0"><%= @project.name %></h1>
    <%= status_badge(@project.status) %>
    <%= progress_status_badge(@project.progress_status) %>
    <%= overdue_badge if @project.overdue? %>
    <p class="text-muted mb-0">Tipo: <%= @project.project_type.name %></p>
```

- [ ] **Step 8: Add the badges to `tracker.html.erb`'s per-project header**

Edit `app/views/projects/tracker.html.erb` — replace:

```erb
        <%= link_to project.name, project_path(project), class: "fw-bold text-decoration-none fs-5" %>
        <%= status_badge(project.status) %>
```

with:

```erb
        <%= link_to project.name, project_path(project), class: "fw-bold text-decoration-none fs-5" %>
        <%= status_badge(project.status) %>
        <%= progress_status_badge(project.progress_status) %>
        <%= overdue_badge if project.overdue? %>
```

- [ ] **Step 9: Add an "Estado" column to `_stage_table.html.erb`**

Replace `app/views/projects/_stage_table.html.erb` in full:

```erb
<%= form_with model: project do |f| %>
  <table class="table table-sm table-bordered mb-0 stage-table">
    <thead>
      <tr><th>Etapa</th><th>Inicio</th><th>Fin</th><th>% Avance</th><th>Estado</th></tr>
    </thead>
    <tbody>
      <%= f.fields_for :project_stages, project.project_stages.includes(:stage_template).order(:id) do |sf| %>
        <tr id="stage-<%= sf.object.id %>">
          <td><%= sf.object.name %></td>
          <td><%= sf.hidden_field :id %><%= sf.date_field :start_date, class: "form-control form-control-sm fecha-input" %></td>
          <td><%= sf.date_field :end_date, class: "form-control form-control-sm fecha-input" %></td>
          <td><%= sf.number_field :progress_percent, min: 0, max: 100, class: "form-control form-control-sm avance-input" %></td>
          <td>
            <%= progress_status_badge(sf.object.progress_status) %>
            <%= overdue_badge if sf.object.overdue? %>
          </td>
        </tr>
      <% end %>
    </tbody>
  </table>
  <%= f.submit "Guardar cambios", class: "btn btn-primary btn-sm mt-3" %>
<% end %>
```

- [ ] **Step 10: Run the tests to verify they pass**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: PASS (all tests)

- [ ] **Step 11: Run the full suite**

Run: `bin/rails test`
Expected: PASS

- [ ] **Step 12: Manual verification**

Run: `bin/rails server`:
- Open a project's detail page — confirm the header shows the status badge, the new progress-status badge, and (if a stage's date has passed without finishing) the red "Vencido" badge.
- Confirm the stage table now has an "Estado" column showing each stage's own progress status and overdue badge independently.
- Open "Seguimiento" — confirm the same badges appear in each project's header line and in its stage table.
- Edit a stage's end date to a past date without setting it to 100% — confirm "Vencido" appears after saving (reload the page, or observe the badge doesn't update live via the drag-to-save JS — that's expected, this task doesn't touch the JS, only server-rendered badges).

- [ ] **Step 13: Commit**

```bash
git add app/helpers/application_helper.rb app/views/projects/show.html.erb app/views/projects/tracker.html.erb \
  app/views/projects/_stage_table.html.erb test/helpers/application_helper_test.rb test/controllers/projects_controller_test.rb
git commit -m "Show progress-status and Vencido badges on the project header, Seguimiento, and stage table"
```

---

## Final verification

- [ ] Run `bin/rails test` once more — expect a clean pass.
