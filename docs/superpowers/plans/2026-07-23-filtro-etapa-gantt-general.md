# Filtro por etapa en el Gantt general — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user pick a stage (e.g., "Instalación") on `projects#index` and see each project's Gantt bar drawn with that specific stage's date range instead of the project's full span.

**Architecture:** A single additive, view-only change. `ProjectsController#index` gains one instance variable (`@stage_names`) to populate the dropdown — it does not touch the `@projects` query at all. The view's `gantt_tasks` construction switches from `Array#map` to `Array#filter_map`, using each project's own `project_stage` (matched by name) when a stage filter is active, and dropping projects that don't have that stage. The table and KPI cards are untouched.

**Tech Stack:** Rails 7.2.3 controller/view code, Minitest integration tests.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-23-filtro-etapa-gantt-general-design.md`.
- This is a Gantt-only filter — it must NOT affect `@projects`, the "Listado" table, or the KPI cards (Total/Vencidos/Finalizados). Those must keep showing exactly what the other filters (Tipo/Estado/Instalador/Desde-Hasta/Buscar) already produce.
- Stage matching is by `ProjectStage#name` (a plain string, copied from `StageTemplate#name` at creation) — never by `stage_template_id`, so it works correctly even across multiple `ProjectType`s that happen to share a stage name.
- A project with no `project_stage` matching the chosen name is simply omitted from `gantt_tasks` — not an error, not a fallback to the full range.
- Bar coloring stays by installer — unchanged, no new CSS.
- This plan only touches `projects#index` — `projects#tracker` (Seguimiento) is out of scope.

---

## File Structure

- Modify `app/controllers/projects_controller.rb` — add `@stage_names = StageTemplate.distinct.order(:name).pluck(:name)` to `index`.
- Modify `app/views/projects/index.html.erb` — add the "Etapa" `<select>` to the filters form; change `gantt_tasks` from `.map` to `.filter_map` with the stage-lookup branch.
- Modify `test/controllers/projects_controller_test.rb` — add tests for the new filter (existing file, same controller test suite used by every prior round on this screen).

---

### Task 1: Stage filter for the general Gantt

**Files:**
- Modify: `app/controllers/projects_controller.rb:4-18` (the `index` action).
- Modify: `app/views/projects/index.html.erb:38-45` (add the Etapa field) and `:93-112` (the `gantt_tasks`/`gantt_colors` block).
- Test: `test/controllers/projects_controller_test.rb`.

**Interfaces:**
- Consumes: `StageTemplate#name` (existing column), `ProjectStage#name` (existing column, copied from the stage template at creation via `Project#build_stages_from_template`), `Project#project_stages` (existing association), `Project#gantt_window` (existing method, unchanged).
- Produces: `@stage_names` (an `Array` of distinct stage-template name strings) — consumed only by the view in this same task; no other task depends on it (this is the only task in the plan).

- [ ] **Step 1: Write the failing tests**

Add to `test/controllers/projects_controller_test.rb` (near the other Gantt-related tests):

```ruby
  test "index's Gantt shows only the filtered stage's date range for each project, not the full project span" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    stage = project.project_stages.find_by(name: "Instalación")
    stage.update!(start_date: Date.new(2026, 9, 1), end_date: Date.new(2026, 9, 10))

    get projects_path, params: { stage_name: "Instalación" }
    assert_response :success
    assert_select "script#gantt-tasks" do |elements|
      tasks = JSON.parse(elements.first.text)
      task = tasks.find { |t| t["id"] == project.id.to_s }
      assert_equal "2026-09-01", task["start"]
      assert_equal "2026-09-10", task["end"]
    end
  end

  test "index's Gantt omits a project that has no stage matching the filtered name" do
    other_type = ProjectType.create!(name: "Mantenimiento", slug: "mantenimiento")
    sin_esa_etapa = Project.create!(project_type: other_type, name: "Sin Esa Etapa", custom_fields: {})

    get projects_path, params: { stage_name: "Instalación" }
    assert_response :success
    assert_select "script#gantt-tasks" do |elements|
      tasks = JSON.parse(elements.first.text)
      assert_nil tasks.find { |t| t["id"] == sin_esa_etapa.id.to_s }
    end
  end

  test "index's Gantt without a stage filter still shows each project's full range" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get projects_path
    assert_response :success
    assert_select "script#gantt-tasks" do |elements|
      tasks = JSON.parse(elements.first.text)
      task = tasks.find { |t| t["id"] == project.id.to_s }
      first, last = project.gantt_window
      assert_equal first.to_s, task["start"]
      assert_equal last.to_s, task["end"]
    end
  end

  test "index's stage filter doesn't affect the Listado table or KPI cards" do
    other_type = ProjectType.create!(name: "Mantenimiento", slug: "mantenimiento")
    Project.create!(project_type: project_types(:instalaciones), name: "Con Etapa", custom_fields: {})
    Project.create!(project_type: other_type, name: "Sin Esa Etapa", custom_fields: {})

    get projects_path, params: { stage_name: "Instalación" }
    assert_response :success
    assert_select ".card .display-6", "2"
    assert_select "a[href=?]", project_path(Project.find_by(name: "Sin Esa Etapa"))
  end

  test "index shows an Etapa dropdown with the distinct stage template names" do
    get projects_path
    assert_response :success
    assert_select "select#stage_name option", text: "Instalación"
    assert_select "select#stage_name option", text: "Producción"
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n "/stage|Etapa/"`
Expected: FAIL — `params[:stage_name]` is currently ignored, and there's no `stage_name` `<select>` in the form yet.

- [ ] **Step 3: Add `@stage_names` to the controller**

In `app/controllers/projects_controller.rb`, add this line to `index`, alongside the other view-support variables at the top of the method:

```ruby
    @stage_names = StageTemplate.distinct.order(:name).pluck(:name)
```

So `index` reads:

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

- [ ] **Step 4: Add the Etapa field to the view**

In `app/views/projects/index.html.erb`, find the "Buscar" field:

```erb
      <div class="col-auto">
        <%= form.label :q, "Buscar", class: "form-label" %>
        <%= form.text_field :q, value: params[:q], class: "form-control", placeholder: "Nombre, cliente, dirección..." %>
      </div>
```

Replace it with (adding the Etapa field before it):

```erb
      <div class="col-auto">
        <%= form.label :stage_name, "Etapa", class: "form-label" %>
        <%= form.select :stage_name, @stage_names,
              { include_blank: "Todas", selected: params[:stage_name] }, class: "form-select" %>
      </div>
      <div class="col-auto">
        <%= form.label :q, "Buscar", class: "form-label" %>
        <%= form.text_field :q, value: params[:q], class: "form-control", placeholder: "Nombre, cliente, dirección..." %>
      </div>
```

- [ ] **Step 5: Change `gantt_tasks` to filter by stage**

In `app/views/projects/index.html.erb`, find:

```erb
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
```

Replace it with:

```erb
  <%
    gantt_tasks = projects_list.filter_map do |project|
      if params[:stage_name].present?
        stage = project.project_stages.find { |s| s.name == params[:stage_name] }
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
```

Note `gantt_colors` is intentionally left unchanged — it still derives from the full `projects_list`, not from `gantt_tasks`, so it keeps coloring by installer for every project regardless of whether that project has a visible bar in the filtered Gantt.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/projects_controller.rb app/views/projects/index.html.erb test/controllers/projects_controller_test.rb
git commit -m "Add stage filter to the general Gantt on projects#index"
```

---

## Final Verification

- [ ] Run the full test suite: `bin/rails test`
- [ ] Expected: all tests pass, no regressions anywhere else in the app.
