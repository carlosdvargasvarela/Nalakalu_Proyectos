# Secciones por tipo de proyecto (acordeón) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure `projects#index` into a Bootstrap accordion with one self-contained section per `ProjectType` — each with its own filters, pagination, Gantt (with its own Etapa options), and Listado table with bulk-assign.

**Architecture:** This is a single, atomic task — the controller and view must change together (the old view breaks immediately if only the controller changes, and vice versa), so it cannot be split into independently-shippable sub-tasks. `ProjectsController#index` builds an `@sections` array (one hash per `ProjectType`, produced by a new private `build_section` method). `index.html.erb` becomes the accordion wrapper; a new partial `_project_type_section.html.erb` holds the per-section content (filters, KPIs, Gantt, bulk-assign, table, pagination) that used to live directly in `index.html.erb`. Every filter/pagination param is nested under `sections[<project_type.slug>]` so sections never interfere with each other.

**Tech Stack:** Rails 7.2.3 controller/view code, Minitest integration tests, Bootstrap 5.3.3 accordion component (already loaded via CDN, no new dependencies).

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-23-secciones-por-tipo-proyecto-design.md`.
- Every section is independent: its own filters (Estado, Instalador, Etapa, Desde/Hasta, Buscar), its own pagination, its own Gantt, its own Listado table with bulk-assign.
- Params are namespaced as `sections[<slug>][...]` — verified via `bin/rails runner` that `form_with(scope: "sections[<slug>]")` produces this nesting correctly (e.g. `name="sections[instalaciones][status]"`, `id="sections_instalaciones_status"`).
- Pagination links must use `request.query_parameters.deep_merge("sections" => { slug => { "page" => n } })` — a shallow `.merge` would wipe out every other section's filters/page.
- The "Tipo" filter field is removed entirely — sectioning by type replaces it.
- Every DOM id that used to be page-unique must become section-unique with a `-<slug>` suffix: `#gantt-<slug>`, `#gantt-tasks-<slug>`, `#bulk-assign-form-<slug>`, `#bulk-assign-installer-select-<slug>`, `#select-all-projects-<slug>`.
- `bulk_assign_installer` (the controller action) is unchanged — it still reads plain `params[:installer_id]`/`params[:project_ids]`, not nested under `sections`.
- No new gems, no new JS libraries — the accordion is pure Bootstrap (already loaded).
- This plan only touches `projects#index` — `projects#tracker` (Seguimiento) is out of scope.

---

## File Structure

- Modify `app/controllers/projects_controller.rb` — replace `index`'s body with a loop building `@sections`; add `build_section` private method.
- Modify `app/views/projects/index.html.erb` — becomes the accordion wrapper only.
- Create `app/views/projects/_project_type_section.html.erb` — the per-section content (filters, KPIs, Gantt, bulk-assign, table, pagination), rendered once per `ProjectType`.
- Modify `test/controllers/projects_controller_test.rb` — update every test whose assertions reference the old unscoped structure; add new tests for the sectioning behavior itself.

---

### Task 1: Accordion sections per project type

**Files:**
- Modify: `app/controllers/projects_controller.rb:4-20` (the `index` action) and add a `build_section` private method.
- Modify: `app/views/projects/index.html.erb` (entire file — becomes the accordion wrapper).
- Create: `app/views/projects/_project_type_section.html.erb`.
- Test: `test/controllers/projects_controller_test.rb`.

**Interfaces:**
- Consumes: `Project`, `ProjectType`, `StageTemplate`, `Installer` (all existing models), `filter_by_installer`/`filter_by_no_installer`/`filter_by_date_range`/`filter_by_query` (existing private methods, unchanged signatures — still take `(scope, ...)` and return a relation).
- Produces: `@sections` — an `Array` of `Hash`es, one per `ProjectType`, each with keys `:project_type`, `:params`, `:projects_list`, `:page_projects`, `:page`, `:total_pages`, `:stage_names`. This is the only task in the plan — nothing downstream depends on it.

- [ ] **Step 1: Write the new sectioning-specific tests**

Add these to `test/controllers/projects_controller_test.rb` (place them near the other Gantt/filter tests — exact position doesn't matter, Minitest runs alphabetically by default file order doesn't affect correctness):

```ruby
  test "index shows each project type as its own section, listing only that type's own projects" do
    other_type = ProjectType.create!(name: "Mantenimiento", slug: "mantenimiento")
    torre = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    otro = Project.create!(project_type: other_type, name: "Proyecto Otro Tipo", custom_fields: {})

    get projects_path
    assert_response :success
    assert_select "a[href=?]", project_path(torre)
    assert_select "a[href=?]", project_path(otro)
    assert_select ".accordion-item", count: ProjectType.count
  end

  test "index's accordion expands the first section and collapses the rest" do
    ProjectType.create!(name: "Mantenimiento", slug: "mantenimiento")
    get projects_path
    assert_response :success
    assert_select ".accordion-collapse.show", count: 1
  end

  test "index's filter for one section doesn't affect another section's results" do
    other_type = ProjectType.create!(name: "Mantenimiento", slug: "mantenimiento")
    torre = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {}, status: "active")
    otro = Project.create!(project_type: other_type, name: "Proyecto Otro Tipo", custom_fields: {}, status: "active")

    get projects_path, params: { sections: { project_types(:instalaciones).slug => { status: "archived" } } }
    assert_response :success
    assert_select "a[href=?]", project_path(torre), count: 0
    assert_select "a[href=?]", project_path(otro)
  end

  test "index's pagination for one section doesn't affect another section's page" do
    other_type = ProjectType.create!(name: "Mantenimiento", slug: "mantenimiento")
    25.times { |n| Project.create!(project_type: project_types(:instalaciones), name: "Proyecto #{n}", custom_fields: {}) }
    otro = Project.create!(project_type: other_type, name: "Proyecto Otro Tipo", custom_fields: {})

    get projects_path, params: { sections: { project_types(:instalaciones).slug => { page: 2 } } }
    assert_response :success
    assert_select "a[href=?]", project_path(otro)
  end

  test "index's Etapa dropdown only lists stages belonging to that section's own project type" do
    other_type = ProjectType.create!(name: "Mantenimiento", slug: "mantenimiento")
    StageTemplate.create!(project_type: other_type, name: "Etapa De Otro Tipo", position: 1)

    get projects_path
    assert_response :success
    assert_select "select#sections_#{project_types(:instalaciones).slug}_stage_name option", text: "Instalación"
    assert_select "select#sections_#{project_types(:instalaciones).slug}_stage_name option", text: "Etapa De Otro Tipo", count: 0
  end

  test "index's ids are unique per section (Gantt, bulk-assign form, select-all checkbox)" do
    other_type = ProjectType.create!(name: "Mantenimiento", slug: "mantenimiento")
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    Project.create!(project_type: other_type, name: "Proyecto Otro Tipo", custom_fields: {})

    get projects_path
    assert_response :success
    assert_select "#gantt-#{project_types(:instalaciones).slug}"
    assert_select "#gantt-#{other_type.slug}"
    assert_select "#bulk-assign-form-#{project_types(:instalaciones).slug}"
    assert_select "#bulk-assign-form-#{other_type.slug}"
    assert_select "#select-all-projects-#{project_types(:instalaciones).slug}"
    assert_select "#select-all-projects-#{other_type.slug}"
  end
```

- [ ] **Step 2: Run the new tests to verify they fail**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n "/accordion|section|unique per section/"`
Expected: FAIL — `@sections`/the accordion markup don't exist yet.

- [ ] **Step 3: Rewrite the controller**

In `app/controllers/projects_controller.rb`, replace:

```ruby
  def index
    @project_types = ProjectType.all
    @statuses = Project.distinct.pluck(:status).compact
    @installers = Installer.all
    @stage_names = StageTemplate.distinct.order(:name).pluck(:name)
    @projects = Project.includes(:project_type, project_stages: :stage_template).order(:name)
    @projects = params[:status].present? ? @projects.where(status: params[:status]) : @projects.where.not(status: "archived")
    @projects = @projects.where(project_type_id: params[:project_type_id]) if params[:project_type_id].present?
    if params[:installer_id] == "none"
      @projects = filter_by_no_installer(@projects)
    elsif params[:installer_id].present?
      @projects = filter_by_installer(@projects, params[:installer_id])
    end
    @projects = filter_by_date_range(@projects, params[:from_date], params[:to_date])
    @projects = filter_by_query(@projects, params[:q])
    @page = [params[:page].to_i, 1].max
  end
```

with:

```ruby
  def index
    @statuses = Project.distinct.pluck(:status).compact
    @installers = Installer.all
    @sections = ProjectType.all.map { |project_type| build_section(project_type) }
  end
```

Add this private method directly after `filter_by_query` (the last private method, just before the closing `end` of the class):

```ruby
  def build_section(project_type)
    section_params = params.dig(:sections, project_type.slug) || {}

    projects = Project.where(project_type: project_type).includes(:project_type, project_stages: :stage_template).order(:name)
    projects = section_params[:status].present? ? projects.where(status: section_params[:status]) : projects.where.not(status: "archived")
    if section_params[:installer_id] == "none"
      projects = filter_by_no_installer(projects)
    elsif section_params[:installer_id].present?
      projects = filter_by_installer(projects, section_params[:installer_id])
    end
    projects = filter_by_date_range(projects, section_params[:from_date], section_params[:to_date])
    projects = filter_by_query(projects, section_params[:q])

    projects_list = projects.to_a
    per_page = 20
    page = [section_params[:page].to_i, 1].max
    total_pages = (projects_list.size / per_page.to_f).ceil
    page_projects = projects_list.drop((page - 1) * per_page).first(per_page)
    stage_names = StageTemplate.where(project_type: project_type).order(:name).pluck(:name)

    {
      project_type: project_type,
      params: section_params,
      projects_list: projects_list,
      page_projects: page_projects,
      page: page,
      total_pages: total_pages,
      stage_names: stage_names
    }
  end
```

- [ ] **Step 4: Rewrite `index.html.erb` as the accordion wrapper**

Replace the ENTIRE content of `app/views/projects/index.html.erb` with:

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

<div class="accordion" id="projectsAccordion">
  <% @sections.each_with_index do |section, index| %>
    <% slug = section[:project_type].slug %>
    <div class="accordion-item">
      <h2 class="accordion-header">
        <button class="accordion-button <%= "collapsed" unless index == 0 %>" type="button"
                data-bs-toggle="collapse" data-bs-target="#collapse-<%= slug %>">
          <%= section[:project_type].name %> (<%= section[:projects_list].size %>)
        </button>
      </h2>
      <div id="collapse-<%= slug %>" class="accordion-collapse collapse <%= "show" if index == 0 %>"
           data-bs-parent="#projectsAccordion">
        <div class="accordion-body">
          <%= render "project_type_section", section: section %>
        </div>
      </div>
    </div>
  <% end %>
</div>
```

- [ ] **Step 5: Create the per-section partial**

Create `app/views/projects/_project_type_section.html.erb`:

```erb
<%
  project_type = section[:project_type]
  slug = project_type.slug
  section_params = section[:params]
%>

<div class="card mb-4">
  <div class="card-body">
    <%= form_with url: projects_path, method: :get, local: true, scope: "sections[#{slug}]", class: "row g-2" do |form| %>
      <div class="col-auto">
        <%= form.label :status, "Estado", class: "form-label" %>
        <%= form.select :status, @statuses.map { |s| [status_label(s), s] },
              { include_blank: "Todos", selected: section_params[:status] }, class: "form-select" %>
      </div>
      <div class="col-auto">
        <%= form.label :installer_id, "Instalador", class: "form-label" %>
        <%= form.select :installer_id,
              [["Sin instalador", "none"]] + @installers.collect { |i| [i.name, i.id] },
              { include_blank: "Todos", selected: section_params[:installer_id] }, class: "form-select" %>
      </div>
      <div class="col-auto">
        <%= form.label :from_date, "Desde", class: "form-label" %>
        <%= form.date_field :from_date, value: section_params[:from_date], class: "form-control" %>
      </div>
      <div class="col-auto">
        <%= form.label :to_date, "Hasta", class: "form-label" %>
        <%= form.date_field :to_date, value: section_params[:to_date], class: "form-control" %>
      </div>
      <div class="col-auto">
        <%= form.label :stage_name, "Etapa", class: "form-label" %>
        <%= form.select :stage_name, section[:stage_names],
              { include_blank: "Todas", selected: section_params[:stage_name] }, class: "form-select" %>
      </div>
      <div class="col-auto">
        <%= form.label :q, "Buscar", class: "form-label" %>
        <%= form.text_field :q, value: section_params[:q], class: "form-control", placeholder: "Nombre, cliente, dirección..." %>
      </div>
      <div class="col-auto align-self-end">
        <%= form.submit "Filtrar", class: "btn btn-primary" %>
      </div>
    <% end %>
  </div>
</div>

<% if section[:projects_list].empty? %>
  <p>No hay proyectos con estos filtros.</p>
<% else %>
  <%
    projects_list = section[:projects_list]
    page_projects = section[:page_projects]
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
    gantt_tasks = projects_list.filter_map do |project|
      if section_params[:stage_name].present?
        stage = project.project_stages.find { |s| s.name == section_params[:stage_name] }
        next if stage.nil?
        stage_start = stage.start_date || project.created_at.to_date
        stage_end = stage.end_date || (stage_start + 7.days)
        first, last = stage_start, stage_end
      else
        first, last = project.gantt_window
      end
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
    <div class="card-header">Cronograma</div>
    <div class="card-body">
      <style>
        .gantt .bar-label {
          font-weight: bold;
        }
        <% gantt_colors.each do |installer_id, color| %>
          .gantt .bar-wrapper.installer-color-<%= installer_id %> .bar,
          .gantt .bar-wrapper.installer-color-<%= installer_id %>:hover .bar,
          .gantt .bar-wrapper.installer-color-<%= installer_id %>.active .bar {
            fill: <%= color %>;
          }
        <% end %>
      </style>

      <div id="gantt-<%= slug %>" class="mb-0" style="max-height: 630px; overflow-y: auto;"></div>

      <script type="application/json" id="gantt-tasks-<%= slug %>"><%== gantt_tasks.to_json %></script>

      <script src="https://cdn.jsdelivr.net/npm/frappe-gantt@0.6.1/dist/frappe-gantt.min.js"></script>
      <script>
        document.addEventListener("DOMContentLoaded", function () {
          var tasks = JSON.parse(document.getElementById("gantt-tasks-<%= slug %>").textContent);
          if (tasks.length > 0) {
            var gantt = new Gantt("#gantt-<%= slug %>", tasks, {
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

  <%= form_with url: bulk_assign_installer_projects_path(request.query_parameters), method: :patch, local: true,
        id: "bulk-assign-form-#{slug}", class: "d-flex gap-2 align-items-end mb-3" do |f| %>
    <div>
      <%= f.label :installer_id, "Asignar instalador a los seleccionados", for: "bulk-assign-installer-select-#{slug}", class: "form-label" %>
      <%= f.select :installer_id, @installers.collect { |i| [i.name, i.id] },
            { include_blank: "Elegí un instalador" }, class: "form-select", id: "bulk-assign-installer-select-#{slug}" %>
    </div>
    <%= f.submit "Asignar", class: "btn btn-primary" %>
  <% end %>

  <div class="card mb-4">
    <div class="card-header">Listado</div>
    <div class="card-body p-0">
      <table class="table table-striped mb-0">
        <thead>
          <tr>
            <th><input type="checkbox" id="select-all-projects-<%= slug %>"></th>
            <th>Nombre</th><th>Estado</th><th>Avance</th><th></th>
          </tr>
        </thead>
        <tbody>
          <% page_projects.each do |project| %>
            <tr>
              <td><%= check_box_tag "project_ids[]", project.id, false, id: nil, form: "bulk-assign-form-#{slug}" %></td>
              <td><%= link_to project.name, project_path(project) %></td>
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
      <% if section[:total_pages] > 1 %>
        <nav class="p-3">
          <ul class="pagination mb-0">
            <li class="page-item <%= "disabled" if section[:page] <= 1 %>">
              <%= link_to "Anterior", projects_path(request.query_parameters.deep_merge("sections" => { slug => { "page" => section[:page] - 1 } })), class: "page-link" %>
            </li>
            <% (1..section[:total_pages]).each do |n| %>
              <li class="page-item <%= "active" if n == section[:page] %>">
                <%= link_to n, projects_path(request.query_parameters.deep_merge("sections" => { slug => { "page" => n } })), class: "page-link" %>
              </li>
            <% end %>
            <li class="page-item <%= "disabled" if section[:page] >= section[:total_pages] %>">
              <%= link_to "Siguiente", projects_path(request.query_parameters.deep_merge("sections" => { slug => { "page" => section[:page] + 1 } })), class: "page-link" %>
            </li>
          </ul>
        </nav>
      <% end %>
    </div>
  </div>

  <script>
    document.getElementById("select-all-projects-<%= slug %>").addEventListener("change", function (e) {
      document.querySelectorAll('input[form="bulk-assign-form-<%= slug %>"]').forEach(function (cb) { cb.checked = e.target.checked; });
    });
  </script>
<% end %>
```

- [ ] **Step 6: Run the new tests to verify they pass**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n "/accordion|section|unique per section/"`
Expected: all PASS.

- [ ] **Step 7: Run the full test file to see which pre-existing tests break**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: many FAILURES — every pre-existing `index`-related test that referenced the old unscoped structure (`#gantt`, `#bulk-assign-form`, `select#status`, `select#installer_id`, `select#stage_name`, `input[name=from_date]`/`to_date`/`q`, unnested filter/page params, the removed "Tipo" filter, `.card-header` text "Cronograma general"). This is expected — Step 8 fixes them.

- [ ] **Step 8: Update every pre-existing test broken by the restructure**

Find each test below by its exact name (`grep -n 'test "..."'`) in `test/controllers/projects_controller_test.rb` and replace its body with the version shown here. Every other `index`-related test not listed here needs NO change (its assertions don't reference any id/param that changed).

Replace `test "index shows one Gantt task per project by default"`:
```ruby
  test "index shows one Gantt task per project by default" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get projects_path
    assert_response :success
    assert_select "script#gantt-tasks-#{project_types(:instalaciones).slug}", text: /#{project.name}/
  end
```

Replace `test "index renders the Gantt container with a fixed max-height and vertical scroll"`:
```ruby
  test "index renders the Gantt container with a fixed max-height and vertical scroll" do
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get projects_path
    assert_response :success
    assert_select "#gantt-#{project_types(:instalaciones).slug}[style=?]", "max-height: 630px; overflow-y: auto;"
  end
```

Replace `test "index's Gantt shows only the filtered stage's date range for each project, not the full project span"`:
```ruby
  test "index's Gantt shows only the filtered stage's date range for each project, not the full project span" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    stage = project.project_stages.find_by(name: "Instalación")
    stage.update!(start_date: Date.new(2026, 9, 1), end_date: Date.new(2026, 9, 10))
    slug = project_types(:instalaciones).slug

    get projects_path, params: { sections: { slug => { stage_name: "Instalación" } } }
    assert_response :success
    assert_select "script#gantt-tasks-#{slug}" do |elements|
      tasks = JSON.parse(elements.first.text)
      task = tasks.find { |t| t["id"] == project.id.to_s }
      assert_equal "2026-09-01", task["start"]
      assert_equal "2026-09-10", task["end"]
    end
  end
```

Replace `test "index's Gantt omits a project that has no stage matching the filtered name"` (the old cross-type premise no longer applies now that sections are per-type — every project of a type has every stage template belonging to that type, so the only way a section's Gantt can omit a project is filtering by a stage name that doesn't exist for that type at all):
```ruby
  test "index's Gantt section omits every project when the filtered stage doesn't exist for that type" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    slug = project_types(:instalaciones).slug

    get projects_path, params: { sections: { slug => { stage_name: "Etapa Inexistente" } } }
    assert_response :success
    assert_select "script#gantt-tasks-#{slug}" do |elements|
      tasks = JSON.parse(elements.first.text)
      assert_nil tasks.find { |t| t["id"] == project.id.to_s }
    end
  end
```

Replace `test "index's Gantt without a stage filter still shows each project's full range"`:
```ruby
  test "index's Gantt without a stage filter still shows each project's full range" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    slug = project_types(:instalaciones).slug
    get projects_path
    assert_response :success
    assert_select "script#gantt-tasks-#{slug}" do |elements|
      tasks = JSON.parse(elements.first.text)
      task = tasks.find { |t| t["id"] == project.id.to_s }
      first, last = project.gantt_window
      assert_equal first.to_s, task["start"]
      assert_equal last.to_s, task["end"]
    end
  end
```

Replace `test "index's stage filter doesn't affect the Listado table or KPI cards"`:
```ruby
  test "index's stage filter doesn't affect that section's Listado table or KPI cards" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Con Etapa", custom_fields: {})
    slug = project_types(:instalaciones).slug

    get projects_path, params: { sections: { slug => { stage_name: "Etapa Inexistente" } } }
    assert_response :success
    assert_select ".card .display-6", "1"
    assert_select "a[href=?]", project_path(project)
  end
```

Replace `test "index shows an Etapa dropdown with the distinct stage template names"`:
```ruby
  test "index shows an Etapa dropdown with the distinct stage template names" do
    get projects_path
    assert_response :success
    slug = project_types(:instalaciones).slug
    assert_select "select#sections_#{slug}_stage_name option", text: "Instalación"
    assert_select "select#sections_#{slug}_stage_name option", text: "Producción"
  end
```

Replace `test "index filters by project_type"` (the "Tipo" filter is removed — this now verifies the sectioning itself):
```ruby
  test "index shows each project type as its own section, listing only that type's own projects" do
    other_type = ProjectType.create!(name: "Mantenimiento", slug: "mantenimiento")
    torre = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    otro = Project.create!(project_type: other_type, name: "Proyecto Otro Tipo", custom_fields: {})

    get projects_path
    assert_response :success
    assert_select "a[href=?]", project_path(torre)
    assert_select "a[href=?]", project_path(otro)
    assert_select ".accordion-item", count: ProjectType.count
  end
```
(This is identical to one of the Step 1 tests — if Step 1 already added it verbatim under this exact name, delete this duplicate instead of adding it twice.)

Replace `test "index filters by status"`:
```ruby
  test "index filters by status" do
    slug = project_types(:instalaciones).slug
    torre = Project.create!(
      project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {}, status: "active"
    )
    vieja = Project.create!(
      project_type: project_types(:instalaciones), name: "Torre Vieja", custom_fields: {}, status: "archived"
    )

    get projects_path, params: { sections: { slug => { status: "archived" } } }
    assert_response :success
    assert_match(/#{vieja.name}/, response.body)
    assert_no_match(/#{torre.name}/, response.body)
  end
```

Replace `test "index filters by installer"`:
```ruby
  test "index filters by installer" do
    slug = project_types(:instalaciones).slug
    otro_instalador = Installer.create!(name: "Otro Instalador")
    con_juan = Project.create!(
      project_type: project_types(:instalaciones), name: "Con Juan", custom_fields: { instalador: installers(:juan_perez).id }
    )
    con_otro = Project.create!(
      project_type: project_types(:instalaciones), name: "Con Otro", custom_fields: { instalador: otro_instalador.id }
    )

    get projects_path, params: { sections: { slug => { installer_id: installers(:juan_perez).id } } }
    assert_response :success
    assert_match(/#{con_juan.name}/, response.body)
    assert_no_match(/#{con_otro.name}/, response.body)
  end
```

Replace `test "index filters by Sin instalador"`:
```ruby
  test "index filters by Sin instalador" do
    slug = project_types(:instalaciones).slug
    sin_instalador = Project.create!(
      project_type: project_types(:instalaciones), name: "Sin Instalador", custom_fields: {}
    )
    con_instalador = Project.create!(
      project_type: project_types(:instalaciones), name: "Con Instalador",
      custom_fields: { instalador: installers(:juan_perez).id }
    )

    get projects_path, params: { sections: { slug => { installer_id: "none" } } }
    assert_response :success
    assert_match(/#{sin_instalador.name}/, response.body)
    assert_no_match(/#{con_instalador.name}/, response.body)
  end
```

Replace `test "index shows a Sin instalador option in the Instalador filter"`:
```ruby
  test "index shows a Sin instalador option in the Instalador filter" do
    get projects_path
    assert_response :success
    slug = project_types(:instalaciones).slug
    assert_select "select#sections_#{slug}_installer_id option[value=?]", "none", text: "Sin instalador"
  end
```

Replace `test "index shows a message and no Gantt when no projects match the filters"`:
```ruby
  test "index shows a message and no Gantt when no projects match the filters" do
    slug = project_types(:instalaciones).slug
    get projects_path, params: { sections: { slug => { status: "nonexistent-status" } } }
    assert_response :success
    assert_select "body", /No hay proyectos con estos filtros/
    assert_select "#gantt-#{slug}", count: 0
  end
```

Replace `test "index shows Spanish labels in the status filter while keeping English values"`:
```ruby
  test "index shows Spanish labels in the status filter while keeping English values" do
    Project.create!(
      project_type: project_types(:instalaciones), name: "Torre Vieja", custom_fields: {}, status: "archived"
    )
    get projects_path
    assert_response :success
    slug = project_types(:instalaciones).slug
    assert_select "select#sections_#{slug}_status option[value=?]", "archived", text: "Archivado"
  end
```

Replace `test "index wraps the Gantt and the table in cards"`:
```ruby
  test "index wraps the Gantt and the table in cards" do
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get projects_path
    assert_response :success
    assert_select ".card .card-header", "Cronograma"
    assert_select ".card .card-header", "Listado"
  end
```

Replace `test "bulk_assign_installer preserves existing query params on redirect"`:
```ruby
  test "bulk_assign_installer preserves existing query params on redirect" do
    installer = installers(:juan_perez)
    project = Project.create!(project_type: project_types(:instalaciones), name: "Proyecto A", custom_fields: {})
    slug = project_types(:instalaciones).slug

    patch bulk_assign_installer_projects_path(sections: { slug => { status: "archived" } }), params: {
      installer_id: installer.id, project_ids: [project.id]
    }

    assert_redirected_to projects_path(sections: { slug => { status: "archived" } })
  end
```

Replace `test "index's bulk-assign form action preserves the current installer filter"`:
```ruby
  test "index's bulk-assign form action preserves the current installer filter" do
    slug = project_types(:instalaciones).slug
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get projects_path, params: { sections: { slug => { installer_id: "none" } } }
    assert_response :success
    assert_select "form#bulk-assign-form-#{slug}[action=?]",
      bulk_assign_installer_projects_path(sections: { slug => { installer_id: "none" } })
  end
```

Replace `test "index renders a bulk-assign form with a checkbox per project, not nested inside another form"`:
```ruby
  test "index renders a bulk-assign form with a checkbox per project, not nested inside another form" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    slug = project_types(:instalaciones).slug
    get projects_path
    assert_response :success

    assert_select "form#bulk-assign-form-#{slug}[action=?]", bulk_assign_installer_projects_path
    assert_select "form#bulk-assign-form-#{slug} select[name=?]", "installer_id"
    assert_select "form#bulk-assign-form-#{slug} input[type=submit][value=?]", "Asignar"
    assert_select "input[type=checkbox][name=?][form=bulk-assign-form-#{slug}]", "project_ids[]", value: project.id.to_s

    doc = Nokogiri::HTML5(response.body)
    bulk_form = doc.at_css("#bulk-assign-form-#{slug}")
    assert_nil bulk_form.at_css("form"), "the archive button's form must not be nested inside the bulk-assign form"
  end
```

Replace `test "index's select-all checkbox toggles every project checkbox via JS"`:
```ruby
  test "index's select-all checkbox toggles every project checkbox via JS" do
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get projects_path
    assert_response :success
    slug = project_types(:instalaciones).slug
    assert_select "input#select-all-projects-#{slug}[type=checkbox]"
    assert_match(/select-all-projects-#{slug}/, response.body)
    assert_match(/project_ids\[\]/, response.body)
  end
```

Replace `test "index's pagination Anterior link points to the previous page, not itself"`:
```ruby
  test "index's pagination Anterior link points to the previous page, not itself" do
    slug = project_types(:instalaciones).slug
    25.times { |n| Project.create!(project_type: project_types(:instalaciones), name: "Proyecto #{n}", custom_fields: {}) }
    get projects_path, params: { sections: { slug => { page: 2 } } }
    assert_response :success
    assert_select "a.page-link[href=?]", projects_path(sections: { slug => { page: 1 } })
  end
```

Replace `test "index filters by a Desde/Hasta date range that overlaps a project's stages"`:
```ruby
  test "index filters by a Desde/Hasta date range that overlaps a project's stages" do
    slug = project_types(:instalaciones).slug
    dentro = Project.create!(project_type: project_types(:instalaciones), name: "Dentro del Rango", custom_fields: {})
    dentro.project_stages.order(:id).first.update!(start_date: Date.new(2026, 3, 1), end_date: Date.new(2026, 3, 10))

    fuera = Project.create!(project_type: project_types(:instalaciones), name: "Fuera del Rango", custom_fields: {})
    fuera.project_stages.each { |s| s.update!(start_date: Date.new(2026, 6, 1), end_date: Date.new(2026, 6, 10)) }

    get projects_path, params: { sections: { slug => { from_date: "2026-02-01", to_date: "2026-04-01" } } }
    assert_response :success
    assert_match(/#{dentro.name}/, response.body)
    assert_no_match(/#{fuera.name}/, response.body)
  end
```

Replace `test "index shows Desde and Hasta date fields in the filter form"`:
```ruby
  test "index shows Desde and Hasta date fields in the filter form" do
    get projects_path
    assert_response :success
    slug = project_types(:instalaciones).slug
    assert_select "input[type=date][name=?]", "sections[#{slug}][from_date]"
    assert_select "input[type=date][name=?]", "sections[#{slug}][to_date]"
  end
```

Replace `test "index's Desde/Hasta filter always shows projects with no dated stages, regardless of the range"`:
```ruby
  test "index's Desde/Hasta filter always shows projects with no dated stages, regardless of the range" do
    slug = project_types(:instalaciones).slug
    sin_fechas = Project.create!(project_type: project_types(:instalaciones), name: "Sin Fechas", custom_fields: {})
    fuera = Project.create!(project_type: project_types(:instalaciones), name: "Fuera del Rango", custom_fields: {})
    fuera.project_stages.each { |s| s.update!(start_date: Date.new(2026, 6, 1), end_date: Date.new(2026, 6, 10)) }

    get projects_path, params: { sections: { slug => { from_date: "2026-02-01", to_date: "2026-04-01" } } }
    assert_response :success
    assert_match(/#{sin_fechas.name}/, response.body)
    assert_no_match(/#{fuera.name}/, response.body)
  end
```

Replace `test "index's q filter matches a project by name"`:
```ruby
  test "index's q filter matches a project by name" do
    slug = project_types(:instalaciones).slug
    match = Project.create!(project_type: project_types(:instalaciones), name: "Torre del Bosque", custom_fields: {})
    other = Project.create!(project_type: project_types(:instalaciones), name: "Otro Proyecto", custom_fields: {})

    get projects_path, params: { sections: { slug => { q: "Bosque" } } }
    assert_response :success
    assert_match(/#{match.name}/, response.body)
    assert_no_match(/#{other.name}/, response.body)
  end
```

Replace `test "index's q filter matches a value inside custom_fields, regardless of which field holds it"`:
```ruby
  test "index's q filter matches a value inside custom_fields, regardless of which field holds it" do
    slug = project_types(:instalaciones).slug
    match = Project.create!(
      project_type: project_types(:instalaciones), name: "Proyecto A",
      custom_fields: { cliente: "Constructora Acme S.R.L." }
    )
    other = Project.create!(
      project_type: project_types(:instalaciones), name: "Proyecto B",
      custom_fields: { cliente: "Otro Cliente" }
    )

    get projects_path, params: { sections: { slug => { q: "Acme" } } }
    assert_response :success
    assert_match(/#{match.name}/, response.body)
    assert_no_match(/#{other.name}/, response.body)
  end
```

Replace `test "index's q filter is case-insensitive"`:
```ruby
  test "index's q filter is case-insensitive" do
    slug = project_types(:instalaciones).slug
    project = Project.create!(
      project_type: project_types(:instalaciones), name: "Proyecto Mayúsculas",
      custom_fields: { cliente: "CONSTRUCTORA GRANDE" }
    )

    get projects_path, params: { sections: { slug => { q: "constructora grande" } } }
    assert_response :success
    assert_match(/#{project.name}/, response.body)
  end
```

Replace `test "index's q filter combines with other filters (AND)"` (the old test combined `q` with the now-removed "Tipo" filter — this now combines `q` with `status`, which still exists within a section):
```ruby
  test "index's q filter combines with other filters within the same section (AND)" do
    slug = project_types(:instalaciones).slug
    match = Project.create!(
      project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {}, status: "active"
    )
    otro_estado = Project.create!(
      project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {}, status: "archived"
    )

    get projects_path, params: { sections: { slug => { q: "Torre Norte", status: "active" } } }
    assert_response :success
    assert_select "a[href=?]", project_path(match)
    assert_select "a[href=?]", project_path(otro_estado), count: 0
  end
```

Replace `test "index shows no results when q doesn't match anything"`:
```ruby
  test "index shows no results when q doesn't match anything" do
    slug = project_types(:instalaciones).slug
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get projects_path, params: { sections: { slug => { q: "esto-no-existe-en-ningun-proyecto" } } }
    assert_response :success
    assert_select "body", /No hay proyectos con estos filtros/
  end
```

Replace `test "index shows the q search field in the filter form"`:
```ruby
  test "index shows the q search field in the filter form" do
    get projects_path
    assert_response :success
    slug = project_types(:instalaciones).slug
    assert_select "input[type=text][name=?]", "sections[#{slug}][q]"
  end
```

Replace `test "index paginates the Listado table at 20 projects per page"`:
```ruby
  test "index paginates the Listado table at 20 projects per page" do
    slug = project_types(:instalaciones).slug
    25.times { |n| Project.create!(project_type: project_types(:instalaciones), name: "Proyecto #{n}", custom_fields: {}) }

    get projects_path
    assert_response :success
    assert_select "table tbody tr", count: 20

    get projects_path, params: { sections: { slug => { page: 2 } } }
    assert_response :success
    assert_select "table tbody tr", count: 5
  end
```

Replace `test "index's KPI cards and Gantt tasks count all filtered projects, not just the current page"`:
```ruby
  test "index's KPI cards and Gantt tasks count all filtered projects, not just the current page" do
    slug = project_types(:instalaciones).slug
    25.times { |n| Project.create!(project_type: project_types(:instalaciones), name: "Proyecto #{n}", custom_fields: {}) }

    get projects_path
    assert_response :success
    assert_select ".card .display-6", "25"
    assert_select "script#gantt-tasks-#{slug}" do |elements|
      tasks = JSON.parse(elements.first.text)
      assert_equal 25, tasks.size
    end
  end
```

Replace `test "index shows pagination controls that preserve the current filter"` (the old test preserved the removed "Tipo" filter — this now preserves `status`):
```ruby
  test "index shows pagination controls that preserve the current section's filter" do
    slug = project_types(:instalaciones).slug
    25.times { |n| Project.create!(project_type: project_types(:instalaciones), name: "Proyecto #{n}", custom_fields: {}, status: "active") }

    get projects_path, params: { sections: { slug => { status: "active" } } }
    assert_response :success
    assert_select "ul.pagination"
    assert_select "a.page-link[href=?]", projects_path(sections: { slug => { status: "active", page: 2 } })
  end
```

- [ ] **Step 9: Run the full test file to verify everything passes**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: all PASS. If any test still fails, it references an id/param this plan didn't anticipate — fix that specific test's selector/param nesting following the same `-<slug>` / `sections[<slug>][...]` pattern used throughout this task, without changing what the test verifies.

- [ ] **Step 10: Run the full suite to check for regressions elsewhere**

Run: `bin/rails test`
Expected: all PASS.

- [ ] **Step 11: Commit**

```bash
git add app/controllers/projects_controller.rb app/views/projects/index.html.erb app/views/projects/_project_type_section.html.erb test/controllers/projects_controller_test.rb
git commit -m "Restructure projects#index into an accordion with one section per project type"
```

---

## Final Verification

- [ ] Run the full test suite: `bin/rails test`
- [ ] Expected: all tests pass, no regressions anywhere else in the app.
