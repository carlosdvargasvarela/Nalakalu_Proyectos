# Reordenamiento del listado de proyectos — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reorder `/projects/tipo/:slug` so the Listado table is the second thing the user sees (right after Filtros/Stats), collapse the "Pendientes de fecha" and "Cronograma" panels behind toggles, split the filter row into basic/advanced, and group the navbar's admin links into a dropdown.

**Architecture:** Pure view/JS changes to one ERB partial, one Stimulus controller, and one layout partial. No controller, model, or route changes — `build_section` in `app/controllers/projects_controller.rb` already computes everything the view needs; this plan only touches how it's arranged and revealed.

**Tech Stack:** Rails 7.2 views (ERB), Bootstrap 5 `collapse`/`dropdown` (already loaded, no new JS dependency), Stimulus (`gantt-project-list` controller), Minitest (`ActionDispatch::IntegrationTest` + `assert_select`).

**Spec:** `docs/superpowers/specs/2026-09-17-listado-proyectos-reordenamiento-design.md`

## Global Constraints

- No new gems, no new JS packages — use Bootstrap's built-in `collapse`/`dropdown` JS (already loaded via the asset pipeline for existing modals) and Stimulus (already the project's JS framework).
- No new query params, no new pagination — the "Pendientes de fecha" panel stays unpaginated (see spec, "no se agrega paginación").
- Keep every existing passing test green; where a test asserts exact text that the design intentionally changes (e.g. "Pendientes de fecha" → "Pendientes de fecha (N)"), update that assertion in the same task that changes the markup.
- Views/tests use Spanish copy, matching the rest of the app.

---

### Task 1: Move the Listado card above Pendientes de fecha / Cronograma

**Files:**
- Modify: `app/views/projects/_project_type_section.html.erb`
- Test: `test/controllers/projects_controller_test.rb`

**Interfaces:**
- Consumes: nothing new — uses `section[:projects_list]`, `section[:page_projects]`, `section[:total_pages]`, `slug`, `project_type`, `show_bulk_controls`, `current_user`, all already defined earlier in the partial.
- Produces: no new variables; this task only changes render order. Tasks 2 and 3 will edit the two blocks this task relocates.

- [ ] **Step 1: Write the failing order test**

Add this test to `test/controllers/projects_controller_test.rb`, right after the existing test `"index wraps the Gantt and the table in cards"` (around line 1443):

```ruby
  test "index shows the Listado section before the Cronograma section" do
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_type_projects_path(project_types(:instalaciones).slug)
    assert_response :success
    assert_operator response.body.index("Listado"), :<, response.body.index("Cronograma")
  end

  test "index shows the Listado section before the Pendientes de fecha section" do
    project_types(:instalaciones).update!(require_stage_dates: true)
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_type_projects_path(project_types(:instalaciones).slug)
    assert_response :success
    assert_operator response.body.index("Listado"), :<, response.body.index("Pendientes de fecha")
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n "/Listado section/"`
Expected: both FAIL — today "Cronograma" and "Pendientes de fecha" render *before* "Listado".

- [ ] **Step 3: Move the Pendientes de fecha + Cronograma blocks below the Listado block**

In `app/views/projects/_project_type_section.html.erb`, find this exact block (it currently sits right after the `gantt_colors = ...` Ruby block and right before `<% show_bulk_controls = ... %>`):

```erb
  <% if project_type.require_stage_dates? || project_type.auto_stage_duration_enabled? %>
    <%
      pending_projects = projects_list.filter_map do |project|
        if section[:stage_name].present?
          stage = project.find_stage(section[:stage_name])
          next if stage.nil? || !stage.dates_missing?
          [project, [stage], project.pending_auto_duration_start_date?]
        else
          missing = project.stages_missing_dates
          needs_start = project.pending_auto_duration_start_date?
          [project, missing, needs_start] if missing.any? || needs_start
        end
      end
    %>
    <% if pending_projects.any? %>
      <div class="card mb-4">
        <div class="card-header">Pendientes de fecha</div>
        <div class="card-body p-0">
          <ul class="list-group list-group-flush">
            <% pending_projects.each do |project, missing, needs_start| %>
              <li class="list-group-item d-flex justify-content-between align-items-center flex-wrap gap-2">
                <span>
                  <%= link_to project.name, project_path(project) %>
                  <% if missing.any? %> — falta fecha en: <%= missing.map(&:name).join(", ") %><% end %>
                </span>
                <% if needs_start %>
                  <%= form_with url: apply_auto_duration_project_path(project), method: :post, local: true, class: "d-flex gap-2 align-items-center" do |f| %>
                    <%= f.date_field :start_date, class: "form-control form-control-sm", required: true %>
                    <%= f.submit "Calcular", class: "btn btn-outline-primary btn-sm" %>
                  <% end %>
                <% end %>
              </li>
            <% end %>
          </ul>
        </div>
      </div>
    <% end %>
  <% end %>

  <div class="card mb-4">
    <div class="card-header">Cronograma</div>
    <div class="card-body" data-controller="gantt-project-list"
         data-gantt-project-list-tasks-value="<%= gantt_tasks.to_json %>"
         data-gantt-project-list-colors-value="<%= gantt_colors.to_json %>">
      <div class="btn-group btn-group-sm mb-2" role="group" id="view-mode-<%= slug %>">
        <button type="button" class="btn btn-outline-secondary view-mode-btn active" data-mode="Day"
                data-gantt-project-list-target="viewModeButton" data-action="click->gantt-project-list#changeViewMode">Día</button>
        <button type="button" class="btn btn-outline-secondary view-mode-btn" data-mode="Week"
                data-gantt-project-list-target="viewModeButton" data-action="click->gantt-project-list#changeViewMode">Semana</button>
        <button type="button" class="btn btn-outline-secondary view-mode-btn" data-mode="Month"
                data-gantt-project-list-target="viewModeButton" data-action="click->gantt-project-list#changeViewMode">Mes</button>
        <button type="button" class="btn btn-outline-secondary" data-gantt-project-list-target="sortButton"
                data-action="click->gantt-project-list#toggleSort" title="Invertir orden">
          <i class="bi bi-sort-down"></i>
        </button>
      </div>
      <% if selected_type && gantt_colors.any? %>
        <%= render "gantt_legend", entries: gantt_colors.map { |_, name, color| [name, color] } %>
      <% end %>
      <div id="gantt-<%= slug %>" data-gantt-project-list-target="chart" class="mb-0"></div>

      <script src="https://cdn.jsdelivr.net/npm/frappe-gantt@1.2.2/dist/frappe-gantt.umd.js"></script>
    </div>
  </div>
```

Cut that whole block out, and paste it back in **after** the closing `</div>` of the bulk-assign modal's `<% end %>` — i.e. right before the final `<% end %>` of the partial (the one that closes `<% if section[:projects_list].empty? %> ... <% else %>` from the top of the file). Concretely: the block goes *after* this line:

```erb
    <% end %>
  </div>
```

(that's the closing of `<div data-controller="bulk-select">`) and *before* the file's very last `<% end %>`.

Nothing inside the moved block changes in this task — it's a pure cut-and-paste.

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n "/Listado section/"`
Expected: both PASS.

- [ ] **Step 5: Run the full projects controller test suite to check for regressions**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: PASS (same pass count as before this task, plus the 2 new tests).

- [ ] **Step 6: Commit**

```bash
git add app/views/projects/_project_type_section.html.erb test/controllers/projects_controller_test.rb
git commit -m "Mover el Listado antes de Pendientes de fecha y Cronograma"
```

---

### Task 2: Collapse "Pendientes de fecha" behind a toggle with a count

**Files:**
- Modify: `app/views/projects/_project_type_section.html.erb`
- Modify: `test/controllers/projects_controller_test.rb`

**Interfaces:**
- Consumes: `pending_projects` (array of `[project, missing, needs_start]`), `slug` — both already in scope after Task 1.
- Produces: DOM id `pendientes-fecha-<%= slug %>` on the collapse wrapper, for any future task/test that needs to target it.

- [ ] **Step 1: Update the three tests that assert the old exact header text**

In `test/controllers/projects_controller_test.rb`, each of these three tests creates exactly one pending project, so the new header text is `"Pendientes de fecha (1)"`. Change:

```ruby
    assert_select ".card-header", "Pendientes de fecha"
```

to:

```ruby
    assert_select ".card-header", "Pendientes de fecha (1)"
```

in these three tests (search for the string to find them):
- `"index shows a pendientes de fecha panel listing projects with undated stages, when the type requires dates"`
- `"index shows a pending-start-date row with a date form, for auto-duration types"`
- `"index's pendientes de fecha panel, with a stage filter active, shows a project only if THAT stage lacks a date"`

Do **not** change the four tests that assert `count: 0` (the panel doesn't render at all in those cases — that behavior is unchanged).

- [ ] **Step 2: Add a new test for the collapsed-by-default state**

Add after the test `"index shows a pendientes de fecha panel listing projects with undated stages, when the type requires dates"`:

```ruby
  test "index's pendientes de fecha panel is collapsed by default" do
    project_types(:instalaciones).update!(require_stage_dates: true)
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    slug = project_types(:instalaciones).slug

    get project_type_projects_path(slug)
    assert_response :success
    assert_select "#pendientes-fecha-#{slug}.collapse:not(.show)"
  end
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n "/pendientes de fecha/"`
Expected: the 3 updated tests FAIL (header text still says "Pendientes de fecha" without a count), the new collapsed-state test FAILS (no such id exists yet).

- [ ] **Step 4: Wrap the panel in a collapse**

Replace the "Pendientes de fecha" card in `app/views/projects/_project_type_section.html.erb` (relocated by Task 1):

```erb
    <% if pending_projects.any? %>
      <div class="card mb-4">
        <div class="card-header">Pendientes de fecha</div>
        <div class="card-body p-0">
          <ul class="list-group list-group-flush">
```

with:

```erb
    <% if pending_projects.any? %>
      <div class="card mb-4">
        <div class="card-header">
          <button type="button" class="btn btn-link p-0 text-decoration-none" data-bs-toggle="collapse"
                  data-bs-target="#pendientes-fecha-<%= slug %>" aria-expanded="false" aria-controls="pendientes-fecha-<%= slug %>">
            Pendientes de fecha (<%= pending_projects.size %>)
          </button>
        </div>
        <div class="collapse" id="pendientes-fecha-<%= slug %>">
        <div class="card-body p-0">
          <ul class="list-group list-group-flush">
```

and close the two new wrapping `<div>`s right before the card's final `</div>` — i.e. change:

```erb
          </ul>
        </div>
      </div>
    <% end %>
  <% end %>
```

to:

```erb
          </ul>
        </div>
        </div>
      </div>
    <% end %>
  <% end %>
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n "/pendientes de fecha/"`
Expected: PASS.

- [ ] **Step 6: Run the full projects controller test suite**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: PASS, no regressions.

- [ ] **Step 7: Commit**

```bash
git add app/views/projects/_project_type_section.html.erb test/controllers/projects_controller_test.rb
git commit -m "Colapsar el panel Pendientes de fecha con un contador"
```

---

### Task 3: Collapse "Cronograma" behind a toggle, lazy-init the Gantt chart

**Files:**
- Modify: `app/views/projects/_project_type_section.html.erb`
- Modify: `app/javascript/controllers/gantt_project_list_controller.js`
- Test: `test/controllers/projects_controller_test.rb`

**Interfaces:**
- Consumes: `gantt_tasks`, `gantt_colors`, `selected_type`, `slug` — already in scope.
- Produces: DOM id `cronograma-<%= slug %>` on the collapse wrapper. The Stimulus controller's `connect()` no longer unconditionally builds the chart; it now defers to a `shown.bs.collapse` listener when the chart's card-body starts hidden. This matters for any other view reusing `gantt-project-list` (currently only this partial and `show.html.erb`'s own Gantt use a *different* controller — check `app/javascript/controllers/gantt_stage_editor_controller.js` is untouched, it's a separate file).

- [ ] **Step 1: Write the failing test for the collapsed-by-default state**

Add after the test `"index wraps the Gantt and the table in cards"` in `test/controllers/projects_controller_test.rb`:

```ruby
  test "index's Cronograma panel is collapsed by default" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    slug = project_types(:instalaciones).slug

    get project_type_projects_path(slug)
    assert_response :success
    assert_select "#cronograma-#{slug}.collapse:not(.show)"
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n "/Cronograma panel is collapsed/"`
Expected: FAIL — no such id exists yet.

- [ ] **Step 3: Wrap the Cronograma card in a collapse**

Replace (in the block relocated by Task 1):

```erb
  <div class="card mb-4">
    <div class="card-header">Cronograma</div>
    <div class="card-body" data-controller="gantt-project-list"
```

with:

```erb
  <div class="card mb-4">
    <div class="card-header">
      <button type="button" class="btn btn-link p-0 text-decoration-none" data-bs-toggle="collapse"
              data-bs-target="#cronograma-<%= slug %>" aria-expanded="false" aria-controls="cronograma-<%= slug %>">
        Cronograma
      </button>
    </div>
    <div class="collapse" id="cronograma-<%= slug %>">
    <div class="card-body" data-controller="gantt-project-list"
```

and close the extra `<div>` right before the card's closing `</div>`, i.e. change:

```erb
      <script src="https://cdn.jsdelivr.net/npm/frappe-gantt@1.2.2/dist/frappe-gantt.umd.js"></script>
    </div>
  </div>
```

to:

```erb
      <script src="https://cdn.jsdelivr.net/npm/frappe-gantt@1.2.2/dist/frappe-gantt.umd.js"></script>
    </div>
    </div>
  </div>
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n "/Cronograma panel is collapsed/"`
Expected: PASS.

- [ ] **Step 5: Run the full projects controller test suite**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: PASS, no regressions (the existing Gantt-data tests read `data-gantt-project-list-tasks-value` directly via `json_data_attribute`, which doesn't care whether the element is visible).

- [ ] **Step 6: Commit the view change**

```bash
git add app/views/projects/_project_type_section.html.erb test/controllers/projects_controller_test.rb
git commit -m "Colapsar el panel Cronograma"
```

- [ ] **Step 7: Lazy-init the Gantt chart so it doesn't render into a hidden (0-width) container**

`frappe-gantt` measures its container's width when constructed; a `.collapse` element without `.show` is `display: none`, so building the chart in `connect()` (which fires immediately on page load, before the user ever opens the panel) would size it to zero. Update `app/javascript/controllers/gantt_project_list_controller.js`:

Replace:

```js
  connect() {
    if (this.tasksValue.length === 0) return

    this.ascending = true
    this.gantt = new Gantt(this.chartTarget, this.tasksValue, {
      language: "es",
      readonly_dates: true,
      readonly_progress: true,
      today_button: false,
      container_height: 630,
      view_mode_select: false,
      // frappe-gantt defaults infinite_padding to true, which wipes and
      // redraws every bar (this.clear() + this.render()) when the user
      // scrolls near an edge - that loses the --bar-fill custom property
      // applyColors() set on the old nodes. We don't need scroll-driven
      // date-range extension (tasksValue is already the full, fixed set).
      infinite_padding: false,
      popup_on: "hover",
      on_click: (task) => { window.location = task.edit_url },
      popup: (ctx) => this.buildPopup(ctx.task)
    })
    this.applyColors()
  }
```

with:

```js
  connect() {
    if (this.tasksValue.length === 0) return

    const collapseEl = this.element.closest(".collapse")
    if (collapseEl && !collapseEl.classList.contains("show")) {
      collapseEl.addEventListener("shown.bs.collapse", () => this.initGantt(), { once: true })
    } else {
      this.initGantt()
    }
  }

  initGantt() {
    this.ascending = true
    this.gantt = new Gantt(this.chartTarget, this.tasksValue, {
      language: "es",
      readonly_dates: true,
      readonly_progress: true,
      today_button: false,
      container_height: 630,
      view_mode_select: false,
      // frappe-gantt defaults infinite_padding to true, which wipes and
      // redraws every bar (this.clear() + this.render()) when the user
      // scrolls near an edge - that loses the --bar-fill custom property
      // applyColors() set on the old nodes. We don't need scroll-driven
      // date-range extension (tasksValue is already the full, fixed set).
      infinite_padding: false,
      popup_on: "hover",
      on_click: (task) => { window.location = task.edit_url },
      popup: (ctx) => this.buildPopup(ctx.task)
    })
    this.applyColors()
  }
```

There is no JS test suite in this project (confirmed: no `test/javascript` directory, no Jest/Vitest config) — this step has no automated test, consistent with every other Stimulus controller in the codebase.

- [ ] **Step 8: Manually verify in the browser**

Run: `bin/rails server -p 3050` (or reuse a running instance), sign in, open `/projects/tipo/instalaciones`, click the "Cronograma" toggle.
Expected: the Gantt chart renders at full width immediately when the panel opens (not squished, not blank).

- [ ] **Step 9: Commit the JS change**

```bash
git add app/javascript/controllers/gantt_project_list_controller.js
git commit -m "Inicializar el Gantt del listado solo al abrir el panel Cronograma"
```

---

### Task 4: Split filters into basic (always visible) and advanced (behind "Más filtros")

**Files:**
- Modify: `app/views/projects/_project_type_section.html.erb`
- Test: `test/controllers/projects_controller_test.rb`

**Interfaces:**
- Consumes: `form`, `section_params`, `project_type`, `section` — already in scope in the filter form block.
- Produces: DOM id `filtros-avanzados-<%= slug %>` for the advanced-filters collapse.

- [ ] **Step 1: Write the failing test**

Add near the existing test `"index's filter card has a Filtros title"` (around line 1372) in `test/controllers/projects_controller_test.rb`:

```ruby
  test "index's advanced filters are collapsed by default behind a 'Más filtros' toggle" do
    slug = project_types(:instalaciones).slug
    get project_type_projects_path(slug)
    assert_response :success
    assert_select "button", text: "Más filtros"
    assert_select "#filtros-avanzados-#{slug}.collapse:not(.show)"
    assert_select "#filtros-avanzados-#{slug} select#responsible_type_id"
    assert_select "#filtros-avanzados-#{slug} input[type=date][name=?]", "from_date"
  end

  test "index's basic filters (Estado, Buscar) stay outside the advanced-filters collapse" do
    slug = project_types(:instalaciones).slug
    get project_type_projects_path(slug)
    assert_response :success
    assert_select "form.row select#status"
    assert_select "form.row input[type=text][name=?]", "q"
    assert_select "#filtros-avanzados-#{slug} select#status", count: 0
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n "/filters/"`
Expected: both FAIL — there's no "Más filtros" button or `filtros-avanzados-*` element yet.

- [ ] **Step 3: Split the filter form**

In `app/views/projects/_project_type_section.html.erb`, replace the whole filter form body:

```erb
<%= panel_card("Filtros") do %>
  <%= form_with url: project_type_projects_path(slug), method: :get, local: true, class: "row g-2" do |form| %>
    <div class="col-auto">
      <%= form.label :status, "Estado", class: "form-label" %>
      <%= form.select :status, @statuses.map { |s| [status_label(s), s] },
            { include_blank: "Todos", selected: section_params[:status] }, class: "form-select" %>
    </div>
    <div class="col-auto">
      <%= form.label :responsible_type_id, "Tipo de responsable", class: "form-label" %>
      <%= form.select :responsible_type_id, project_type.responsible_types.order(:name).collect { |t| [t.name, t.id] },
            { include_blank: "Todos", selected: section_params[:responsible_type_id] }, class: "form-select" %>
    </div>
    <div class="col-auto">
      <%= form.label :responsible_id, "Responsable", class: "form-label" %>
      <%= form.select :responsible_id,
            [["Sin asignar", "none"]] + Responsible.joins(:project_responsibles).where(project_responsibles: { responsible_type_id: section_params[:responsible_type_id] }).distinct.order(:name).collect { |r| [r.name, r.id] },
            { include_blank: "Todos", selected: section_params[:responsible_id] }, class: "form-select", data: { controller: "tom-select" } %>
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
            { include_blank: "Todas", selected: section[:stage_name] }, class: "form-select" %>
    </div>
    <div class="col-auto">
      <%= form.label :q, "Buscar", class: "form-label" %>
      <%= form.text_field :q, value: section_params[:q], class: "form-control", placeholder: "Nombre, cliente, dirección..." %>
    </div>
    <div class="col-auto align-self-end">
      <%= form.submit "Filtrar", class: "btn btn-primary" %>
      <%= link_to "Quitar filtros", project_type_projects_path(slug), class: "btn btn-outline-secondary" %>
    </div>
  <% end %>
<% end %>
```

with:

```erb
<%= panel_card("Filtros") do %>
  <%= form_with url: project_type_projects_path(slug), method: :get, local: true, class: "row g-2" do |form| %>
    <div class="col-auto">
      <%= form.label :status, "Estado", class: "form-label" %>
      <%= form.select :status, @statuses.map { |s| [status_label(s), s] },
            { include_blank: "Todos", selected: section_params[:status] }, class: "form-select" %>
    </div>
    <div class="col-auto">
      <%= form.label :q, "Buscar", class: "form-label" %>
      <%= form.text_field :q, value: section_params[:q], class: "form-control", placeholder: "Nombre, cliente, dirección..." %>
    </div>
    <div class="col-auto align-self-end">
      <%= form.submit "Filtrar", class: "btn btn-primary" %>
      <%= link_to "Quitar filtros", project_type_projects_path(slug), class: "btn btn-outline-secondary" %>
      <button type="button" class="btn btn-outline-secondary" data-bs-toggle="collapse"
              data-bs-target="#filtros-avanzados-<%= slug %>" aria-expanded="false" aria-controls="filtros-avanzados-<%= slug %>">
        Más filtros
      </button>
    </div>
    <div class="collapse w-100" id="filtros-avanzados-<%= slug %>">
      <div class="row g-2 mt-1">
        <div class="col-auto">
          <%= form.label :responsible_type_id, "Tipo de responsable", class: "form-label" %>
          <%= form.select :responsible_type_id, project_type.responsible_types.order(:name).collect { |t| [t.name, t.id] },
                { include_blank: "Todos", selected: section_params[:responsible_type_id] }, class: "form-select" %>
        </div>
        <div class="col-auto">
          <%= form.label :responsible_id, "Responsable", class: "form-label" %>
          <%= form.select :responsible_id,
                [["Sin asignar", "none"]] + Responsible.joins(:project_responsibles).where(project_responsibles: { responsible_type_id: section_params[:responsible_type_id] }).distinct.order(:name).collect { |r| [r.name, r.id] },
                { include_blank: "Todos", selected: section_params[:responsible_id] }, class: "form-select", data: { controller: "tom-select" } %>
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
                { include_blank: "Todas", selected: section[:stage_name] }, class: "form-select" %>
        </div>
      </div>
    </div>
  <% end %>
<% end %>
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n "/filters/"`
Expected: PASS.

- [ ] **Step 5: Run the full projects controller test suite**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: PASS, no regressions (all other filter tests only assert field presence/selected values by `id`/`name`, unaffected by the collapse wrapper).

- [ ] **Step 6: Commit**

```bash
git add app/views/projects/_project_type_section.html.erb test/controllers/projects_controller_test.rb
git commit -m "Separar filtros básicos y avanzados en el listado"
```

---

### Task 5: Group navbar admin links into a dropdown, label the pending-dates badge

**Files:**
- Modify: `app/views/layouts/_navbar.html.erb`
- Test: `test/controllers/navbar_test.rb`

**Interfaces:**
- Consumes: `current_user.admin?`, `admin_project_types_path`, `admin_responsibles_path`, `admin_project_type_associations_path`, `admin_users_path` — unchanged, already in scope.
- Produces: nothing consumed elsewhere.

- [ ] **Step 1: Write the failing tests**

The existing tests in `test/controllers/navbar_test.rb` (`"navbar shows session-aware links when signed in"`, `"navbar includes a link to Responsables for admin"`, `"navbar includes a link to Tipos de asociación for admin"`, and their gerente-hides-it counterparts) already assert `assert_select "nav a[href=?]", <path>` — that keeps working whether the link is a direct child or inside a dropdown menu, so they don't need to change. Add one new test after `"navbar includes a link to Tipos de asociación for admin"` (around line 46):

```ruby
  test "navbar groups the admin links under an Administración dropdown" do
    sign_in users(:juan)
    get root_path
    assert_response :success
    assert_select "nav .dropdown-menu a[href=?]", admin_project_types_path
    assert_select "nav .dropdown-menu a[href=?]", admin_responsibles_path
    assert_select "nav .dropdown-menu a[href=?]", admin_project_type_associations_path
    assert_select "nav .dropdown-menu a[href=?]", admin_users_path
  end

  test "navbar's pending-dates badge has an accessible label" do
    project_types(:instalaciones).update!(require_stage_dates: true)
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})

    sign_in users(:juan)
    get root_path
    assert_response :success
    assert_select "nav a[href=?] + .badge[title=?]", projects_path, "1 proyecto(s) con fecha pendiente"
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/controllers/navbar_test.rb -n "/Administración dropdown|accessible label/"`
Expected: both FAIL — no `.dropdown-menu` exists yet, no `title` attribute on the badge yet.

- [ ] **Step 3: Group the admin links into a dropdown and label the badge**

In `app/views/layouts/_navbar.html.erb`, replace:

```erb
      <%= link_to "Proyectos", projects_path, class: "nav-link" %>
      <% if user_signed_in? %>
        <% pending_count = pending_stage_dates_count(current_user) %>
        <% if pending_count > 0 %>
          <span class="badge bg-danger"><%= pending_count %></span>
        <% end %>
      <% end %>
      <%= link_to "Seguimiento", tracker_projects_path, class: "nav-link" %>
      <% if user_signed_in? && (current_user.admin? || current_user.gerente?) %>
        <%= link_to "Importar", new_import_path, class: "nav-link" %>
      <% end %>
      <% if user_signed_in? && current_user.admin? %>
        <%= link_to "Administración", admin_project_types_path, class: "nav-link" %>
        <%= link_to "Responsables", admin_responsibles_path, class: "nav-link" %>
        <%= link_to "Tipos de asociación", admin_project_type_associations_path, class: "nav-link" %>
        <%= link_to "Usuarios", admin_users_path, class: "nav-link" %>
      <% end %>
```

with:

```erb
      <%= link_to "Proyectos", projects_path, class: "nav-link" %>
      <% if user_signed_in? %>
        <% pending_count = pending_stage_dates_count(current_user) %>
        <% if pending_count > 0 %>
          <span class="badge bg-danger" title="<%= pending_count %> proyecto(s) con fecha pendiente"><%= pending_count %></span>
        <% end %>
      <% end %>
      <%= link_to "Seguimiento", tracker_projects_path, class: "nav-link" %>
      <% if user_signed_in? && (current_user.admin? || current_user.gerente?) %>
        <%= link_to "Importar", new_import_path, class: "nav-link" %>
      <% end %>
      <% if user_signed_in? && current_user.admin? %>
        <div class="nav-item dropdown">
          <a class="nav-link dropdown-toggle" href="#" role="button" data-bs-toggle="dropdown" aria-expanded="false">
            Administración
          </a>
          <ul class="dropdown-menu">
            <li><%= link_to "Tipos de proyecto", admin_project_types_path, class: "dropdown-item" %></li>
            <li><%= link_to "Responsables", admin_responsibles_path, class: "dropdown-item" %></li>
            <li><%= link_to "Tipos de asociación", admin_project_type_associations_path, class: "dropdown-item" %></li>
            <li><%= link_to "Usuarios", admin_users_path, class: "dropdown-item" %></li>
          </ul>
        </div>
      <% end %>
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/controllers/navbar_test.rb`
Expected: PASS — including the pre-existing tests, since they only look for `nav a[href=?]` without requiring it to be a direct child.

- [ ] **Step 5: Run the full test suite for a final regression check**

Run: `bin/rails test`
Expected: PASS, same failures/errors count as `main` before this work started (this repo's pre-existing baseline — see `git log` commit "Corregir los 15 fallos preexistentes de la suite" — should be 0 now; if any new failure appears it must be fixed before moving on).

- [ ] **Step 6: Commit**

```bash
git add app/views/layouts/_navbar.html.erb test/controllers/navbar_test.rb
git commit -m "Agrupar enlaces de administración en un dropdown y etiquetar el badge de pendientes"
```

---

## Post-implementation cleanup

- [ ] Remove the 8 seed projects created during design verification (`Instalación #100`–`#107`) from the local dev database, if they're still present:

```bash
bin/rails runner 'Project.where("name LIKE ?", "Instalación #%").destroy_all'
```

- [ ] Stop the ad-hoc dev server if it was started only for this work: `kill $(cat tmp/pids/server.pid)`.
