# Rework de la página de inicio (Proyectos) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn `projects#index` into a small dashboard — KPI cards (Total/Vencidos/Finalizados), card-wrapped Gantt and table, the progress-status/overdue badges already used elsewhere in the app, and a header dropdown for creating a new project (replacing the loose list at the bottom of the page).

**Architecture:** One view rewrite (`projects/index.html.erb`) plus one layout addition (Bootstrap's JS bundle, needed for the new dropdown to function — this app has only ever loaded Bootstrap's CSS). No controller/model changes — `ProjectsController#index`'s query logic is untouched; only the view's presentation of the same `@projects` changes.

**Tech Stack:** Ruby on Rails, Minitest, Bootstrap 5.3.3 (CSS already used; this plan adds its JS bundle from the same CDN/version).

## Global Constraints

- No changes to `ProjectsController#index`'s filtering logic (status/project_type/installer) — only the view changes.
- The Bootstrap JS bundle must be added before the dropdown markup is added — a dropdown with `data-bs-toggle="dropdown"` does nothing without it (confirmed: this app currently loads only Bootstrap's CSS `<link>`, never its JS).
- `projects_list = @projects.to_a` is computed once and reused for the KPI counts, the Gantt task/color maps, and the table loop — avoid re-querying `@projects` multiple times in the view.

---

### Task 1: Bootstrap JS bundle + full index.html.erb rework

**Files:**
- Modify: `app/views/layouts/application.html.erb`
- Modify: `app/views/projects/index.html.erb`
- Modify: `test/controllers/projects_controller_test.rb`

**Interfaces:**
- Consumes: `Project#progress_status`/`#overdue?` (already exist, from an earlier round), `ApplicationHelper#status_badge`/`#progress_status_badge`/`#overdue_badge` (already exist), `ApplicationHelper#status_label` (already exists, used by the Estado filter).
- Produces: nothing consumed by a later task — this is the only task in this plan.

- [ ] **Step 1: Write the failing tests**

Add to `test/controllers/projects_controller_test.rb`, inside the existing test class:

```ruby
  test "index shows a Nuevo proyecto dropdown with one link per project type" do
    other_type = ProjectType.create!(name: "Mantenimiento", slug: "mantenimiento")
    get projects_path
    assert_response :success
    assert_select ".dropdown-menu a[href=?]", new_project_path(project_type_id: project_types(:instalaciones).id)
    assert_select ".dropdown-menu a[href=?]", new_project_path(project_type_id: other_type.id)
  end

  test "index shows KPI cards for total, overdue, and finalizado projects" do
    Project.create!(project_type: project_types(:instalaciones), name: "Activo", custom_fields: {})
    vencido = Project.create!(project_type: project_types(:instalaciones), name: "Vencido", custom_fields: {})
    vencido.project_stages.order(:id).first.update!(end_date: Date.current - 1.day, progress_percent: 50)
    finalizado = Project.create!(project_type: project_types(:instalaciones), name: "Finalizado", custom_fields: {})
    finalizado.project_stages.each { |stage| stage.update!(progress_percent: 100) }

    get projects_path
    assert_response :success
    assert_select ".card .display-6", "3"
    assert_select ".card .display-6.text-danger", "1"
    assert_select ".card .display-6.text-success", "1"
  end

  test "index shows progress-status and overdue badges in the table" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    project.project_stages.order(:id).first.update!(end_date: Date.current - 1.day, progress_percent: 40)

    get projects_path
    assert_response :success
    assert_select "table span.badge.bg-info", "Iniciado"
    assert_select "table span.badge.bg-danger", "Vencido"
  end

  test "index wraps the Gantt and the table in cards" do
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get projects_path
    assert_response :success
    assert_select ".card .card-header", "Cronograma general"
    assert_select ".card .card-header", "Listado"
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: FAIL — no dropdown, no KPI cards, no "Avance" column, no card wrappers exist yet in `index.html.erb`.

- [ ] **Step 3: Add the Bootstrap JS bundle to the layout**

Edit `app/views/layouts/application.html.erb` — add right before `</body>`:

```erb
  <body>
    <%= render "layouts/navbar" %>
    <div class="container py-4">
      <% if notice %>
        <div class="alert alert-success"><%= notice %></div>
      <% end %>
      <% if alert %>
        <div class="alert alert-danger"><%= alert %></div>
      <% end %>
      <%= yield %>
    </div>
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js"></script>
  </body>
```

- [ ] **Step 4: Replace `index.html.erb` in full**

```erb
<div class="d-flex justify-content-between align-items-center mb-3">
  <h1 class="mb-0">Proyectos</h1>
  <div class="dropdown">
    <button class="btn btn-primary dropdown-toggle" type="button" data-bs-toggle="dropdown" aria-expanded="false">
      Nuevo proyecto
    </button>
    <ul class="dropdown-menu dropdown-menu-end">
      <% ProjectType.all.each do |project_type| %>
        <li><%= link_to project_type.name, new_project_path(project_type_id: project_type.id), class: "dropdown-item" %></li>
      <% end %>
    </ul>
  </div>
</div>

<div class="card mb-4">
  <div class="card-body">
    <%= form_with url: projects_path, method: :get, local: true, class: "row g-2" do |form| %>
      <div class="col-auto">
        <%= form.label :project_type_id, "Tipo", class: "form-label" %>
        <%= form.select :project_type_id, @project_types.collect { |pt| [pt.name, pt.id] },
              { include_blank: "Todos", selected: params[:project_type_id] }, class: "form-select" %>
      </div>
      <div class="col-auto">
        <%= form.label :status, "Estado", class: "form-label" %>
        <%= form.select :status, @statuses.map { |s| [status_label(s), s] },
              { include_blank: "Todos", selected: params[:status] }, class: "form-select" %>
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
  </div>
</div>

<% if @projects.none? %>
  <p>No hay proyectos con estos filtros.</p>
<% else %>
  <%
    projects_list = @projects.to_a
  %>
  <div class="row g-3 mb-4">
    <div class="col-sm-4">
      <div class="card text-center">
        <div class="card-body">
          <div class="display-6"><%= projects_list.size %></div>
          <div class="text-muted">Total</div>
        </div>
      </div>
    </div>
    <div class="col-sm-4">
      <div class="card text-center">
        <div class="card-body">
          <div class="display-6 text-danger"><%= projects_list.count(&:overdue?) %></div>
          <div class="text-muted">Vencidos</div>
        </div>
      </div>
    </div>
    <div class="col-sm-4">
      <div class="card text-center">
        <div class="card-body">
          <div class="display-6 text-success"><%= projects_list.count { |p| p.progress_status == "finalizado" } %></div>
          <div class="text-muted">Finalizados</div>
        </div>
      </div>
    </div>
  </div>

  <% content_for :head do %>
    <link href="https://cdn.jsdelivr.net/npm/frappe-gantt@0.6.1/dist/frappe-gantt.css" rel="stylesheet">
  <% end %>

  <%
    gantt_tasks = projects_list.map do |project|
      first, last = project.gantt_window
      progress_values = project.project_stages.map(&:progress_percent)
      average_progress = progress_values.any? ? (progress_values.sum / progress_values.size.to_f).round : 0
      {
        id: project.id.to_s,
        name: project.name,
        start: first.to_s,
        end: last.to_s,
        progress: average_progress,
        edit_url: project_path(project),
        custom_class: "installer-color-#{project.installer&.id || 'none'}"
      }
    end
    gantt_colors = projects_list.map do |project|
      installer = project.installer
      [installer&.id || "none", installer&.color || "#6c757d"]
    end.uniq
  %>

  <div class="card mb-4">
    <div class="card-header">Cronograma general</div>
    <div class="card-body">
      <style>
        <% gantt_colors.each do |installer_id, color| %>
          .gantt .bar-wrapper.installer-color-<%= installer_id %> .bar,
          .gantt .bar-wrapper.installer-color-<%= installer_id %>:hover .bar,
          .gantt .bar-wrapper.installer-color-<%= installer_id %>.active .bar {
            fill: <%= color %>;
          }
        <% end %>
      </style>

      <div id="gantt" class="mb-0"></div>

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
    </div>
  </div>

  <div class="card mb-4">
    <div class="card-header">Listado</div>
    <div class="card-body p-0">
      <table class="table table-striped mb-0">
        <thead>
          <tr><th>Nombre</th><th>Tipo</th><th>Estado</th><th>Avance</th><th></th></tr>
        </thead>
        <tbody>
          <% projects_list.each do |project| %>
            <tr>
              <td><%= link_to project.name, project_path(project) %></td>
              <td><%= project.project_type.name %></td>
              <td><%= status_badge(project.status) %></td>
              <td>
                <%= progress_status_badge(project.progress_status) %>
                <%= overdue_badge if project.overdue? %>
              </td>
              <td>
                <%= link_to "Editar", edit_project_path(project), class: "btn btn-outline-secondary btn-sm" %>
                <%= render "archive_button", project: project %>
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
  </div>
<% end %>
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: PASS (all tests)

- [ ] **Step 6: Run the full suite**

Run: `bin/rails test`
Expected: PASS

- [ ] **Step 7: Manual verification**

Run: `bin/rails server`, open `/projects`:
- Confirm the KPI row shows correct Total/Vencidos/Finalizados counts.
- Confirm clicking "Nuevo proyecto" opens a dropdown (this is the first real test of the newly-added Bootstrap JS bundle — if it doesn't open, the bundle isn't loading correctly, don't skip this check).
- Confirm the Gantt and the project table each render inside a card with a header.
- Confirm the table's new "Avance" column shows the right progress/overdue badges per project.
- Confirm filtering (Tipo/Estado/Instalador) still works exactly as before.
- Confirm "Editar"/"Archivar" still work per row.

- [ ] **Step 8: Commit**

```bash
git add app/views/layouts/application.html.erb app/views/projects/index.html.erb test/controllers/projects_controller_test.rb
git commit -m "Rework the home screen into a dashboard: KPIs, cards, progress badges, dropdown"
```

---

## Final verification

- [ ] Run `bin/rails test` once more — expect a clean pass.
- [ ] `grep -n "Nuevo proyecto" app/views/projects/index.html.erb` shows exactly one occurrence (the dropdown button), confirming the old bottom list is fully gone.
