# Acercar el UI al Excel original — franja de proyecto + tabla compartida — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the vertical "Datos" list on the project detail page and the bordered card-per-project on "Seguimiento" with a horizontal graphite-colored data band (matching the original Excel's per-order color strip), extract the duplicated stage-editing table into one shared partial, and compact the % Avance/date cells.

**Architecture:** Two new shared partials (`_data_band.html.erb`, `_stage_table.html.erb`) consumed by both `projects/show.html.erb` and `projects/tracker.html.erb`, plus two small CSS classes. No controller/model/route changes.

**Tech Stack:** Ruby on Rails, Minitest, Bootstrap (`bg-primary`, already mapped to the graphite theme from an earlier round — no new color).

## Global Constraints

- No controller/model/route changes — this is a view + CSS only change.
- `_stage_table.html.erb` must render identically in both consuming views (same table structure, same `id="stage-<id>"` per row) — the project detail page's Gantt depends on that id for its click-to-scroll behavior; "Seguimiento" simply doesn't use it, which is harmless.
- `_data_band.html.erb` takes `fields:` as a parameter (not hardcoded to `show_in_gantt`) — `show.html.erb` passes *all* of the project type's fields, `tracker.html.erb` passes only the `show_in_gantt` ones, matching each page's existing scope of what it showed before this change.

---

### Task 1: Data band + shared stage table + compact cells

**Files:**
- Create: `app/views/projects/_data_band.html.erb`
- Create: `app/views/projects/_stage_table.html.erb`
- Modify: `app/views/projects/show.html.erb`
- Modify: `app/views/projects/tracker.html.erb`
- Modify: `app/assets/stylesheets/application.css`
- Modify: `test/controllers/projects_controller_test.rb`

**Interfaces:**
- Consumes: `Project#custom_fields`, `Project#project_stages` (unchanged), `ProjectType#field_definitions` (unchanged), `ApplicationHelper#status_badge` (unchanged, from an earlier round).
- Produces: `_data_band` partial (locals: `project:`, `fields:`), `_stage_table` partial (locals: `project:`) — no later task in this plan depends on them, this is the only task.

- [ ] **Step 1: Write the failing tests**

Replace this test in `test/controllers/projects_controller_test.rb`:

```ruby
  test "show groups Datos and Cronograma into cards" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_path(project)
    assert_response :success
    assert_select ".card .card-header", "Datos"
    assert_select ".card .card-header", "Cronograma"
  end
```

with:

```ruby
  test "show renders the project data as a graphite band and keeps the Cronograma card" do
    project = Project.create!(
      project_type: project_types(:instalaciones), name: "Torre Norte",
      custom_fields: { cliente: "Acme S.A." }
    )
    get project_path(project)
    assert_response :success
    assert_select ".bg-primary", /Acme S\.A\./
    assert_select ".card .card-header", "Cronograma"
  end
```

Add to the same file, inside the existing test class:

```ruby
  test "tracker renders each project's data as a graphite band without a bordered card" do
    installer = installers(:juan_perez)
    project = Project.create!(
      project_type: project_types(:instalaciones), name: "Torre Norte",
      custom_fields: { cliente: "Acme S.A.", instalador: installer.id }
    )
    get tracker_projects_path
    assert_response :success
    assert_select ".bg-primary", /Acme S\.A\./
    assert_select ".card", count: 0
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: FAIL — no `.bg-primary` band exists yet on either page, and `tracker` still wraps each project in a `.card`.

- [ ] **Step 3: Create `_data_band.html.erb`**

```erb
<div class="bg-primary text-white px-3 py-2 rounded d-flex flex-wrap gap-4 mb-4">
  <% fields.each do |field| %>
    <div>
      <small class="text-white-50 d-block"><%= field.label %></small>
      <%= project.custom_fields[field.key] %>
    </div>
  <% end %>
</div>
```

- [ ] **Step 4: Create `_stage_table.html.erb`**

```erb
<%= form_with model: project do |f| %>
  <table class="table table-sm table-bordered mb-0 stage-table">
    <thead>
      <tr><th>Etapa</th><th>Inicio</th><th>Fin</th><th>% Avance</th></tr>
    </thead>
    <tbody>
      <%= f.fields_for :project_stages, project.project_stages.includes(:stage_template).order(:id) do |sf| %>
        <tr id="stage-<%= sf.object.id %>">
          <td><%= sf.object.name %></td>
          <td><%= sf.hidden_field :id %><%= sf.date_field :start_date, class: "form-control form-control-sm fecha-input" %></td>
          <td><%= sf.date_field :end_date, class: "form-control form-control-sm fecha-input" %></td>
          <td><%= sf.number_field :progress_percent, min: 0, max: 100, class: "form-control form-control-sm avance-input" %></td>
        </tr>
      <% end %>
    </tbody>
  </table>
  <%= f.submit "Guardar cambios", class: "btn btn-primary btn-sm mt-3" %>
<% end %>
```

- [ ] **Step 5: Update `show.html.erb`**

Replace the "Datos" card block:

```erb
<div class="card mb-4">
  <div class="card-header">Datos</div>
  <ul class="list-group list-group-flush">
    <% @project.project_type.field_definitions.each do |field| %>
      <li class="list-group-item"><strong><%= field.label %>:</strong> <%= @project.custom_fields[field.key] %></li>
    <% end %>
  </ul>
</div>
```

with:

```erb
<%= render "data_band", project: @project, fields: @project.project_type.field_definitions %>
```

Replace the inline `<table>` inside the "Cronograma" card's `card-body` (the `<%= form_with model: @project do |f| %> ... <% end %>` block that renders the stage table) with:

```erb
    <%= render "stage_table", project: @project %>
```

(Everything above it in the `card-body` — the `<style>`, `<div id="gantt">`, the two `<script>` tags — stays exactly as-is; only the trailing form/table block is replaced.)

- [ ] **Step 6: Update `tracker.html.erb`**

Replace the per-project block:

```erb
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
```

with:

```erb
  <% @projects.each do |project| %>
    <div class="mb-4">
      <div class="d-flex justify-content-between align-items-center mb-2">
        <%= link_to project.name, project_path(project), class: "fw-bold text-decoration-none fs-5" %>
        <%= status_badge(project.status) %>
      </div>
      <%= render "data_band", project: project, fields: gantt_fields %>
      <%= render "stage_table", project: project %>
    </div>
  <% end %>
```

- [ ] **Step 7: Add the compact-cell CSS**

Append to `app/assets/stylesheets/application.css`:

```css
.avance-input {
  width: 4.5rem;
  text-align: center;
  background-color: #f1f1f1;
  border-radius: 999px;
}

.fecha-input {
  max-width: 130px;
}
```

- [ ] **Step 8: Run the tests to verify they pass**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: PASS (all tests)

- [ ] **Step 9: Run the full suite**

Run: `bin/rails test`
Expected: PASS

- [ ] **Step 10: Manual verification**

Run: `bin/rails server`:
- Open a project's detail page — confirm the "Datos" list is now a graphite band across the top of the page (before the Cronograma card), showing all its custom fields.
- Confirm the Cronograma card, Gantt, and drag-to-save behavior all still work exactly as before (this task only changed how the stage table's HTML is sourced, not its markup or JS).
- Open "Seguimiento" — confirm each project is a flat band (no bordered card), with the graphite data band showing its `show_in_gantt` fields, followed by its stage table.
- Confirm the % Avance inputs render as a compact centered pill and the date inputs are narrower than before.
- Edit and save a stage in both "Seguimiento" and the project detail page — confirm both still save correctly (this reuses the same underlying `accepts_nested_attributes_for` mechanism, unchanged).

- [ ] **Step 11: Commit**

```bash
git add app/views/projects/_data_band.html.erb app/views/projects/_stage_table.html.erb \
  app/views/projects/show.html.erb app/views/projects/tracker.html.erb \
  app/assets/stylesheets/application.css test/controllers/projects_controller_test.rb
git commit -m "Replace Datos list and per-project cards with an Excel-style graphite data band"
```

---

## Final verification

- [ ] Run `bin/rails test` once more — expect a clean pass.
- [ ] `grep -rn "list-group-item.*field.label\|card-header.*Datos" app/views/projects/show.html.erb` returns nothing — confirms the old vertical Datos list is fully gone, not left half-referenced.
