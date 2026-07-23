# Detalle de proyecto — jerarquía visual y limpieza de duplicados — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give `projects#show` a clear header (name, status, actions) and card-grouped sections (Datos, Cronograma), and delete a small table that duplicated field values already shown elsewhere on the same page.

**Architecture:** Pure view-layer change — no controller or model changes (both `status_badge`/`ProjectsController#update` already exist from prior rounds and need nothing new). The archive button becomes a shared partial since it's now used on two pages with identical markup.

**Tech Stack:** Ruby on Rails, Minitest, Bootstrap 5.3.3 (`.card`/`.list-group-flush`, already available via the CDN link — no new CSS).

## Global Constraints

- No controller/model changes — this task is view-only.
- No new CSS — Bootstrap's `.card`, `.card-header`, `.card-body`, `.list-group-flush` cover the whole layout.
- The Gantt's `<style>`/`<script>` blocks move location (into `.card-body`) but their content is otherwise unchanged from the current committed version — don't alter the Gantt options, colors, or read-only behavior while moving them.

---

### Task 1: Header, cards, shared archive partial, remove the duplicate Gantt-columns table

**Files:**
- Create: `app/views/projects/_archive_button.html.erb`
- Modify: `app/views/projects/index.html.erb` (replace the inline archive form with the partial)
- Modify: `app/views/projects/show.html.erb` (replace in full — header, cards, delete the duplicate table)
- Modify: `test/controllers/projects_controller_test.rb` (rewrite one existing test, add two new ones)

**Interfaces:**
- Consumes: `ApplicationHelper#status_badge` (`app/helpers/application_helper.rb`, unchanged, from the theme round), `Project#project_stages`/`#gantt_window`/`#current_stage` (unchanged).
- Produces: `app/views/projects/_archive_button.html.erb` partial, rendered as `render "archive_button", project: project` — no later task depends on it (this is the only task in this round).

- [ ] **Step 1: Extract the archive button into a partial**

Create `app/views/projects/_archive_button.html.erb`:

```erb
<%= form_with(model: project, local: true, method: :patch, style: "display:inline-block") do |f| %>
  <%= f.hidden_field :status, value: "archived" %>
  <%= f.submit "Archivar", class: "btn btn-outline-danger btn-sm" %>
<% end %>
```

Edit `app/views/projects/index.html.erb` — replace this block (inside the `<td>` in the projects table):

```erb
            <%= form_with(model: project, local: true, method: :patch, style: "display:inline-block") do |f| %>
              <%= f.hidden_field :status, value: "archived" %>
              <%= f.submit "Archivar", class: "btn btn-outline-danger btn-sm" %>
            <% end %>
```

with:

```erb
            <%= render "archive_button", project: project %>
```

- [ ] **Step 2: Run the existing index tests to confirm the extraction didn't change behavior**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n "/index/"`
Expected: PASS (no assertion changes needed here — the rendered HTML is identical, just sourced from a partial now)

- [ ] **Step 3: Write the failing tests for the new `show` header and cards**

Add to `test/controllers/projects_controller_test.rb`, inside the existing test class:

```ruby
  test "show displays a status badge and an archive button" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_path(project)
    assert_response :success
    assert_select "span.badge.bg-success", "Activo"
    assert_select "form[action=?]", project_path(project) do
      assert_select "input[value=?]", "Archivar"
    end
  end

  test "show groups Datos and Cronograma into cards" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_path(project)
    assert_response :success
    assert_select ".card .card-header", "Datos"
    assert_select ".card .card-header", "Cronograma"
  end
```

Replace the existing test (it verified the now-intentionally-removed duplicate table):

```ruby
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
```

with:

```ruby
  test "show displays each custom field's value exactly once (no duplicate Gantt-columns table)" do
    project = Project.create!(
      project_type: project_types(:instalaciones), name: "Torre Norte",
      custom_fields: { cliente: "Acme S.A." }
    )
    get project_path(project)
    assert_response :success
    assert_select "body", text: /Acme S\.A\./, count: 1
  end
```

- [ ] **Step 4: Run the tests to verify they fail**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: FAIL — no `.card`/`.card-header` elements exist yet, no status badge or archive button on `show`, and the "shown exactly once" test fails because the field value currently appears twice (Datos list + the duplicate table).

- [ ] **Step 5: Replace `show.html.erb` in full**

```erb
<div class="d-flex justify-content-between align-items-start mb-3">
  <div>
    <h1 class="d-inline-block me-2 mb-0"><%= @project.name %></h1>
    <%= status_badge(@project.status) %>
    <p class="text-muted mb-0">Tipo: <%= @project.project_type.name %></p>
  </div>
  <div class="d-flex gap-2">
    <%= link_to "Editar", edit_project_path(@project), class: "btn btn-outline-secondary btn-sm" %>
    <%= render "archive_button", project: @project %>
  </div>
</div>

<div class="card mb-4">
  <div class="card-header">Datos</div>
  <ul class="list-group list-group-flush">
    <% @project.project_type.field_definitions.each do |field| %>
      <li class="list-group-item"><strong><%= field.label %>:</strong> <%= @project.custom_fields[field.key] %></li>
    <% end %>
  </ul>
</div>

<% content_for :head do %>
  <link href="https://cdn.jsdelivr.net/npm/frappe-gantt@0.6.1/dist/frappe-gantt.css" rel="stylesheet">
<% end %>

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
<div class="card mb-4">
  <div class="card-header">Cronograma</div>
  <div class="card-body">
    <style>
      <% stage_colors.each do |template_id, color| %>
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
            on_click: function (task) { window.location.hash = "stage-" + task.id; },
            on_date_change: function () { gantt.refresh(tasks); },
            on_progress_change: function () { gantt.refresh(tasks); }
          });
        }
      });
    </script>

    <%= form_with model: @project do |f| %>
      <table class="table table-sm table-bordered w-auto mb-0">
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
      <%= f.submit "Guardar cambios", class: "btn btn-primary mt-3" %>
    <% end %>
  </div>
</div>
```

(Removed entirely, on purpose, per the spec: the `gantt_fields` variable and its `<h2>Gantt</h2>` + conditional `<table>` — that information is already in the "Datos" card above.)

- [ ] **Step 6: Run the tests to verify they pass**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: PASS (all tests)

- [ ] **Step 7: Run the full suite**

Run: `bin/rails test`
Expected: PASS

- [ ] **Step 8: Manual verification**

Run: `bin/rails server`, visit a project's detail page, confirm:
- Name, status badge, and Tipo are grouped in the header, with Editar/Archivar buttons aligned to the right.
- "Datos" and "Cronograma" each render as a bordered card.
- The Gantt chart and the stage-editing table both appear inside the "Cronograma" card, in that order.
- No field value appears twice anywhere on the page.
- Clicking "Archivar" still archives the project (redirects back to the same page, now showing the "Archivado" badge).

- [ ] **Step 9: Commit**

```bash
git add app/views/projects/_archive_button.html.erb app/views/projects/index.html.erb \
  app/views/projects/show.html.erb test/controllers/projects_controller_test.rb
git commit -m "Group project detail page into cards, add status/archive to it, remove duplicate Gantt-columns table"
```

---

## Final verification

- [ ] Run `bin/rails test` once more — expect a clean pass.
- [ ] `grep -rn "gantt_fields" app/` returns nothing (confirms the removed variable and its table are fully gone, not left half-referenced).
