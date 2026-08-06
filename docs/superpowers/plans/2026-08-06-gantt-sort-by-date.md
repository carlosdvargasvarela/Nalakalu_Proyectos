# Gantt Sort By Date Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Order the bars in the project-list Gantt ("Cronograma") by date ascending by default, with a client-side toggle button to reverse the order instantly.

**Architecture:** One `sort_by` call orders the existing `gantt_tasks` array server-side by its already-present `start` field before it's serialized to JSON. A new Stimulus action reverses the in-memory task array and calls Frappe Gantt's `refresh()`, mirroring the existing `changeViewMode` client-side pattern — no server round-trip, no new params.

**Tech Stack:** Rails 7.2 (ERB), Stimulus, Frappe Gantt 1.2.2, Bootstrap Icons (already loaded via CDN), Minitest.

## Global Constraints

- Scope is the Gantt only — the "Listado" table below keeps its existing `Project.order(:name)` ordering, untouched.
- The sort order does not persist across page loads or filter changes — every fresh load starts ascending.
- `start` values in `gantt_tasks` are ISO 8601 date strings (`YYYY-MM-DD`); lexicographic sort equals chronological sort — no `Date.parse` needed.
- No new dependencies, no new URL params.

---

### Task 1: Sort `gantt_tasks` by date ascending

**Files:**
- Modify: `app/views/projects/_project_type_section.html.erb`
- Test: `test/controllers/projects_controller_test.rb`

**Interfaces:**
- Produces: `gantt_tasks` (local ERB variable) is sorted ascending by its `:start` key before being written to `data-gantt-project-list-tasks-value`. Task 2 relies on this being the array order the JS controller receives on page load.

- [ ] **Step 1: Write the failing test**

Add to `test/controllers/projects_controller_test.rb`, near the other "index's Gantt..." tests (e.g. right after `"index shows one Gantt task per project by default"`):

```ruby
  test "index's Gantt tasks are ordered by start date ascending, not by project name" do
    slug = project_types(:instalaciones).slug
    z_project = Project.create!(project_type: project_types(:instalaciones), name: "Zeta", custom_fields: {})
    z_project.project_stages.order(:id).first.update!(start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 1, 5))
    a_project = Project.create!(project_type: project_types(:instalaciones), name: "Alpha", custom_fields: {})
    a_project.project_stages.order(:id).first.update!(start_date: Date.new(2026, 6, 1), end_date: Date.new(2026, 6, 5))

    get project_type_projects_path(slug)
    assert_response :success
    tasks = json_data_attribute('[data-controller="gantt-project-list"]', "data-gantt-project-list-tasks-value")
    ids_in_order = tasks.map { |t| t["id"] }
    assert_operator ids_in_order.index(z_project.id.to_s), :<, ids_in_order.index(a_project.id.to_s)
  end
```

- [ ] **Step 2: Run to confirm it fails**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n test_index_s_Gantt_tasks_are_ordered_by_start_date_ascending_not_by_project_name`
Expected: FAIL — tasks currently come back in `projects_list` order (`Project.order(:name)`), so "Alpha" (name-first) precedes "Zeta" (date-first) instead of the reverse.

- [ ] **Step 3: Sort the array**

In `app/views/projects/_project_type_section.html.erb`, find the `%>` that closes the `gantt_tasks = projects_list.filter_map do |project| ... end` block (right before the `selected_type = ResponsibleType.find_by(...)` line that builds `gantt_colors`). Insert one line right after that `end`, still inside the same `<% %>` Ruby block:

```erb
    gantt_tasks = projects_list.filter_map do |project|
      # ... existing body, unchanged ...
    end
    gantt_tasks = gantt_tasks.sort_by { |task| task[:start] }
    selected_type = ResponsibleType.find_by(id: section_params[:responsible_type_id])
```

- [ ] **Step 4: Run the test to confirm it passes**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n test_index_s_Gantt_tasks_are_ordered_by_start_date_ascending_not_by_project_name`
Expected: PASS

- [ ] **Step 5: Run the full controller test file**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: all PASS, 0 failures — in particular every pre-existing "index's Gantt..." test (they each create a single project, so sort order among one element is a no-op and can't break).

- [ ] **Step 6: Commit**

```bash
git add app/views/projects/_project_type_section.html.erb test/controllers/projects_controller_test.rb
git commit -m "Ordenar las tareas del Gantt de listado por fecha ascendente"
```

---

### Task 2: Client-side toggle to reverse the order

**Files:**
- Modify: `app/views/projects/_project_type_section.html.erb`
- Modify: `app/javascript/controllers/gantt_project_list_controller.js`
- Test: `test/controllers/projects_controller_test.rb`

**Interfaces:**
- Consumes: `gantt_tasks` sorted ascending by `start` (Task 1) — the array the controller receives via `tasksValue` on connect.
- Produces: no new interface for later tasks — this is the last piece of this plan.

- [ ] **Step 1: Write the failing tests**

Add to `test/controllers/projects_controller_test.rb`, right after the test added in Task 1:

```ruby
  test "index's Gantt shows a sort-direction toggle button" do
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    slug = project_types(:instalaciones).slug

    get project_type_projects_path(slug)
    assert_response :success
    assert_select "#view-mode-#{slug} button[data-action=?]", "click->gantt-project-list#toggleSort"
  end

  test "index's Gantt controller JS reverses tasks and refreshes the chart on toggle" do
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_type_projects_path(project_types(:instalaciones).slug)
    assert_response :success
    source = Rails.root.join("app/javascript/controllers/gantt_project_list_controller.js").read
    assert_match(/toggleSort\(/, source)
    assert_match(/this\.gantt\.refresh\(/, source)
  end
```

- [ ] **Step 2: Run to confirm both fail**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n test_index_s_Gantt_shows_a_sort_direction_toggle_button -n test_index_s_Gantt_controller_JS_reverses_tasks_and_refreshes_the_chart_on_toggle`
Expected: both FAIL — no toggle button in the markup yet, no `toggleSort`/`refresh` in the JS yet.

- [ ] **Step 3: Add the toggle button to the view**

In `app/views/projects/_project_type_section.html.erb`, inside the `#view-mode-<%= slug %>` `btn-group` (right after the "Mes" button, still inside the same `<div class="btn-group ...">`), add:

```erb
        <button type="button" class="btn btn-outline-secondary" data-gantt-project-list-target="sortButton"
                data-action="click->gantt-project-list#toggleSort" title="Invertir orden">
          <i class="bi bi-sort-down"></i>
        </button>
```

- [ ] **Step 4: Implement the toggle in the Stimulus controller**

In `app/javascript/controllers/gantt_project_list_controller.js`, make these changes:

Change the `targets` line (line 10) to add `sortButton`:

```javascript
  static targets = ["chart", "viewModeButton", "sortButton"]
```

Add an `ascending` instance flag, set in `connect()`. Replace the `connect()` method body (lines 13-28) with:

```javascript
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
      popup_on: "hover",
      on_click: (task) => { window.location = task.edit_url },
      popup: (ctx) => this.buildPopup(ctx.task)
    })
    this.applyColors()
  }
```

(This is identical to the original except for the added `this.ascending = true` line.)

Add a new `toggleSort()` method, right after `changeViewMode()` (after line 35, before `applyColors()`):

```javascript
  toggleSort() {
    this.ascending = !this.ascending
    const ordered = this.ascending ? this.tasksValue : [...this.tasksValue].reverse()
    this.gantt.refresh(ordered)
    this.applyColors()
    if (this.hasSortButtonTarget) {
      this.sortButtonTarget.querySelector("i").className = this.ascending ? "bi bi-sort-down" : "bi bi-sort-up"
    }
  }
```

`this.tasksValue` itself is never mutated (it stays the ascending array Task 1 produced), so toggling twice returns to the original order.

- [ ] **Step 5: Run both tests to confirm they pass**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n test_index_s_Gantt_shows_a_sort_direction_toggle_button -n test_index_s_Gantt_controller_JS_reverses_tasks_and_refreshes_the_chart_on_toggle`
Expected: both PASS

- [ ] **Step 6: Run the full controller test file**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: all PASS, 0 failures.

- [ ] **Step 7: Manual verification in browser**

Run: `bin/rails server`, sign in, open a project type's listing page with at least two projects with different start dates, and confirm:
- The Gantt bars appear ordered earliest-first.
- Clicking the new toggle button (↓ icon) instantly reverses the bar order (latest-first) and the icon flips to ↑, with no page reload.
- Clicking it again restores the original ascending order and the icon flips back to ↓.
- Switching between Día/Semana/Mes still works normally after toggling sort (colors and click-to-navigate still work on the bars).

Stop the server after checking.

- [ ] **Step 8: Commit**

```bash
git add app/views/projects/_project_type_section.html.erb app/javascript/controllers/gantt_project_list_controller.js test/controllers/projects_controller_test.rb
git commit -m "Agregar toggle para invertir el orden del Gantt de listado"
```
