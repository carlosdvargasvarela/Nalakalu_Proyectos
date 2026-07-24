# Actualización de frappe-gantt: sticky header + Día/Semana/Mes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade frappe-gantt from 0.6.1 to 1.2.2 in both places it's used, gaining a native sticky date header and adding Día/Semana/Mes view-mode buttons (in Spanish, not the library's own English-only selector).

**Architecture:** Two independent tasks, one per Gantt instance: the read-only Gantt in `_project_type_section.html.erb` (projects#index), and the editable drag-to-save Gantt in `show.html.erb`. Each swaps the CDN version, migrates from constructor-option event callbacks to the new `.on(event, fn)` API, replaces manual scroll CSS with the native `container_height` option, and adds 3 Spanish view-mode buttons calling `gantt.change_view_mode(...)`.

**Tech Stack:** Rails 7.2.3 view code, frappe-gantt 1.2.2 (CDN, upgraded from 0.6.1), vanilla JS (no Turbo/Stimulus/jQuery), Minitest.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-24-actualizacion-frappe-gantt-design.md`.
- CDN URLs change from `frappe-gantt@0.6.1/dist/frappe-gantt.min.js` to `frappe-gantt@1.2.2/dist/frappe-gantt.umd.js` (note: the 1.2.2 build filename is `.umd.js`, not `.min.js` — verified against the actual jsdelivr file listing) and CSS from `@0.6.1` to `@1.2.2`.
- Event API migration: `on_click`/`on_date_change`/`on_progress_change` as constructor options → `gantt.on("click", fn)` / `gantt.on("date_change", fn)` / `gantt.on("progress_change", fn)` called after construction.
- The read-only Gantt (`_project_type_section.html.erb`) uses native `readonly_dates: true, readonly_progress: true` instead of the old "refresh to snap back" hack — the `on("date_change"/"progress_change", ...)` handlers are removed entirely for this Gantt (no longer needed).
- The editable Gantt (`show.html.erb`) keeps its `saveStage`/fetch logic and `gantt.refresh(tasks)` error-recovery call — those don't change, only how the events are wired up.
- Both Gantt instances add: `popup: false`, `today_button: false`, `container_height: 630` (replacing the old manual `style="max-height: 630px; overflow-y: auto;"` on the container div), `view_mode_select: false` (we build our own Spanish buttons instead), and 3 buttons ("Día"/data-mode="Day", "Semana"/"Week", "Mes"/"Month") calling `gantt.change_view_mode(btn.dataset.mode)`.
- `custom_class`-based coloring (installer/stage) is unaffected — no CSS changes needed.
- `projects#tracker` has no Gantt of its own (only the shared `_stage_table` editable table) — not touched by this plan.

---

## File Structure

- Modify `app/views/projects/_project_type_section.html.erb` — read-only Gantt upgrade.
- Modify `app/views/projects/show.html.erb` — editable Gantt upgrade.
- Modify `test/controllers/projects_controller_test.rb` — update 3 tests that assert on the old API, add new tests for the new behavior.

---

### Task 1: Upgrade the read-only Gantt (`projects#index`)

**Files:**
- Modify: `app/views/projects/_project_type_section.html.erb:85-150` (the CSS link and the Gantt block).
- Test: `test/controllers/projects_controller_test.rb`.

**Interfaces:** None — self-contained view/JS change, independent of Task 2 (different file, different Gantt instance).

- [ ] **Step 1: Write the failing tests**

In `test/controllers/projects_controller_test.rb`, find and replace this existing test:

```ruby
  test "index configures the Gantt in Spanish with a read-only snap-back on drag" do
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get projects_path
    assert_response :success
    assert_match(/language:\s*"es"/, response.body)
    assert_match(/on_date_change:\s*function\s*\(\)\s*\{\s*gantt\.refresh\(tasks\);\s*\}/, response.body)
  end
```

with:

```ruby
  test "index configures the Gantt in Spanish with native readonly options" do
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get projects_path
    assert_response :success
    assert_match(/language:\s*"es"/, response.body)
    assert_match(/readonly_dates:\s*true/, response.body)
    assert_match(/readonly_progress:\s*true/, response.body)
  end
```

Also find and replace this existing test:

```ruby
  test "index renders the Gantt container with a fixed max-height and vertical scroll" do
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get projects_path
    assert_response :success
    assert_select "#gantt-#{project_types(:instalaciones).slug}[style=?]", "max-height: 630px; overflow-y: auto;"
  end
```

with:

```ruby
  test "index configures the Gantt with a fixed container height instead of manual scroll CSS" do
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get projects_path
    assert_response :success
    slug = project_types(:instalaciones).slug
    assert_select "#gantt-#{slug}[style]", count: 0
    assert_match(/container_height:\s*630/, response.body)
  end
```

Then add these new tests near the ones above:

```ruby
  test "index loads frappe-gantt 1.2.2" do
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get projects_path
    assert_response :success
    assert_match(%r{frappe-gantt@1\.2\.2/dist/frappe-gantt\.css}, response.body)
    assert_match(%r{frappe-gantt@1\.2\.2/dist/frappe-gantt\.umd\.js}, response.body)
    assert_no_match(/frappe-gantt@0\.6\.1/, response.body)
  end

  test "index shows Día/Semana/Mes view-mode buttons for the Gantt" do
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get projects_path
    assert_response :success
    slug = project_types(:instalaciones).slug
    assert_select "#view-mode-#{slug} button", text: "Día"
    assert_select "#view-mode-#{slug} button", text: "Semana"
    assert_select "#view-mode-#{slug} button", text: "Mes"
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n "/readonly options|container height|frappe-gantt 1.2.2|view-mode buttons/"`
Expected: FAIL — old assertions no longer match (already-updated test bodies reference options that don't exist yet), new tests fail because the CDN version/buttons don't exist yet.

- [ ] **Step 3: Upgrade the CSS link**

In `app/views/projects/_project_type_section.html.erb`, replace:

```erb
    <link href="https://cdn.jsdelivr.net/npm/frappe-gantt@0.6.1/dist/frappe-gantt.css" rel="stylesheet">
```

with:

```erb
    <link href="https://cdn.jsdelivr.net/npm/frappe-gantt@1.2.2/dist/frappe-gantt.css" rel="stylesheet">
```

- [ ] **Step 4: Replace the Gantt block**

Replace:

```erb
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
```

with:

```erb
      <div class="btn-group btn-group-sm mb-2" role="group" id="view-mode-<%= slug %>">
        <button type="button" class="btn btn-outline-secondary view-mode-btn active" data-mode="Day">Día</button>
        <button type="button" class="btn btn-outline-secondary view-mode-btn" data-mode="Week">Semana</button>
        <button type="button" class="btn btn-outline-secondary view-mode-btn" data-mode="Month">Mes</button>
      </div>
      <div id="gantt-<%= slug %>" class="mb-0"></div>

      <script type="application/json" id="gantt-tasks-<%= slug %>"><%== gantt_tasks.to_json %></script>

      <script src="https://cdn.jsdelivr.net/npm/frappe-gantt@1.2.2/dist/frappe-gantt.umd.js"></script>
      <script>
        document.addEventListener("DOMContentLoaded", function () {
          var tasks = JSON.parse(document.getElementById("gantt-tasks-<%= slug %>").textContent);
          if (tasks.length > 0) {
            var gantt = new Gantt("#gantt-<%= slug %>", tasks, {
              language: "es",
              readonly_dates: true,
              readonly_progress: true,
              popup: false,
              today_button: false,
              container_height: 630,
              view_mode_select: false
            });
            gantt.on("click", function (task) { window.location = task.edit_url; });

            document.querySelectorAll("#view-mode-<%= slug %> .view-mode-btn").forEach(function (btn) {
              btn.addEventListener("click", function () {
                gantt.change_view_mode(btn.dataset.mode);
                document.querySelectorAll("#view-mode-<%= slug %> .view-mode-btn").forEach(function (b) { b.classList.remove("active"); });
                btn.classList.add("active");
              });
            });
          }
        });
      </script>
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add app/views/projects/_project_type_section.html.erb test/controllers/projects_controller_test.rb
git commit -m "Upgrade the read-only projects#index Gantt to frappe-gantt 1.2.2"
```

---

### Task 2: Upgrade the editable Gantt (`projects#show`)

**Files:**
- Modify: `app/views/projects/show.html.erb:19-116` (the CSS link and the Gantt block).
- Test: `test/controllers/projects_controller_test.rb`.

**Interfaces:** None — self-contained view/JS change, independent of Task 1 (different file, different Gantt instance; both already completed changes to the shared test file will coexist since they touch different tests).

- [ ] **Step 1: Write the failing tests**

In `test/controllers/projects_controller_test.rb`, find and replace this existing test:

```ruby
  test "show's Gantt script saves drag changes via fetch and syncs the stage table" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_path(project)
    assert_response :success
    assert_match(/function saveStage\(/, response.body)
    assert_match(/on_date_change:\s*function\s*\(task,\s*start,\s*end\)/, response.body)
    assert_match(/on_progress_change:\s*function\s*\(task,\s*progress\)/, response.body)
    assert_match(/toDateInputValue/, response.body)
  end
```

with:

```ruby
  test "show's Gantt script saves drag changes via fetch and syncs the stage table" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_path(project)
    assert_response :success
    assert_match(/function saveStage\(/, response.body)
    assert_match(/gantt\.on\(\s*"date_change"\s*,\s*function\s*\(task,\s*start,\s*end\)/, response.body)
    assert_match(/gantt\.on\(\s*"progress_change"\s*,\s*function\s*\(task,\s*progress\)/, response.body)
    assert_match(/toDateInputValue/, response.body)
  end
```

Then add these new tests near it:

```ruby
  test "show loads frappe-gantt 1.2.2" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_path(project)
    assert_response :success
    assert_match(%r{frappe-gantt@1\.2\.2/dist/frappe-gantt\.css}, response.body)
    assert_match(%r{frappe-gantt@1\.2\.2/dist/frappe-gantt\.umd\.js}, response.body)
    assert_no_match(/frappe-gantt@0\.6\.1/, response.body)
  end

  test "show shows Día/Semana/Mes view-mode buttons for the Gantt" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_path(project)
    assert_response :success
    assert_select "#view-mode-show button", text: "Día"
    assert_select "#view-mode-show button", text: "Semana"
    assert_select "#view-mode-show button", text: "Mes"
  end

  test "show's Gantt still reverts a failed save via gantt.refresh" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_path(project)
    assert_response :success
    assert_match(/gantt\.refresh\(tasks\)/, response.body)
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n "/frappe-gantt 1.2.2|view-mode buttons|reverts a failed save|saves drag changes/"`
Expected: FAIL — old assertions no longer match (already-updated test body references the new `.on(...)` calls that don't exist yet), new tests fail because the CDN version/buttons don't exist yet.

- [ ] **Step 3: Upgrade the CSS link**

In `app/views/projects/show.html.erb`, replace:

```erb
<% content_for :head do %>
  <link href="https://cdn.jsdelivr.net/npm/frappe-gantt@0.6.1/dist/frappe-gantt.css" rel="stylesheet">
<% end %>
```

with:

```erb
<% content_for :head do %>
  <link href="https://cdn.jsdelivr.net/npm/frappe-gantt@1.2.2/dist/frappe-gantt.css" rel="stylesheet">
<% end %>
```

- [ ] **Step 4: Replace the Gantt block**

Replace:

```erb
    <div id="gantt" class="mb-4"></div>

    <script type="application/json" id="gantt-tasks"><%== gantt_tasks.to_json %></script>

    <script src="https://cdn.jsdelivr.net/npm/frappe-gantt@0.6.1/dist/frappe-gantt.min.js"></script>
    <script>
      function toDateInputValue(date) {
        var year = date.getFullYear();
        var month = String(date.getMonth() + 1).padStart(2, "0");
        var day = String(date.getDate()).padStart(2, "0");
        return year + "-" + month + "-" + day;
      }

      document.addEventListener("DOMContentLoaded", function () {
        var tasks = JSON.parse(document.getElementById("gantt-tasks").textContent);
        if (tasks.length === 0) return;

        function saveStage(stageId, attrs) {
          fetch("<%= project_path(@project) %>", {
            method: "PATCH",
            headers: {
              "Content-Type": "application/json",
              "Accept": "application/json",
              "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
            },
            body: JSON.stringify({
              project: { project_stages_attributes: { "0": Object.assign({ id: stageId }, attrs) } }
            })
          })
            .then(function (response) {
              if (!response.ok) throw new Error("save failed");
              return response.json();
            })
            .then(function (stages) {
              var updated = stages.find(function (s) { return String(s.id) === String(stageId); });
              if (!updated) return;
              var row = document.getElementById("stage-" + stageId);
              row.querySelector("input[name*='[start_date]']").value = updated.start_date || "";
              row.querySelector("input[name*='[end_date]']").value = updated.end_date || "";
              row.querySelector("input[name*='[progress_percent]']").value = updated.progress_percent;
            })
            .catch(function () {
              gantt.refresh(tasks);
              alert("No se pudo guardar el cambio. Intenta de nuevo.");
            });
        }

        var gantt = new Gantt("#gantt", tasks, {
          language: "es",
          on_click: function (task) { window.location.hash = "stage-" + task.id; },
          on_date_change: function (task, start, end) {
            saveStage(task.id, { start_date: toDateInputValue(start), end_date: toDateInputValue(end) });
          },
          on_progress_change: function (task, progress) {
            saveStage(task.id, { progress_percent: Math.round(progress) });
          }
        });
      });
    </script>
```

with:

```erb
    <div class="btn-group btn-group-sm mb-2" role="group" id="view-mode-show">
      <button type="button" class="btn btn-outline-secondary view-mode-btn active" data-mode="Day">Día</button>
      <button type="button" class="btn btn-outline-secondary view-mode-btn" data-mode="Week">Semana</button>
      <button type="button" class="btn btn-outline-secondary view-mode-btn" data-mode="Month">Mes</button>
    </div>
    <div id="gantt" class="mb-4"></div>

    <script type="application/json" id="gantt-tasks"><%== gantt_tasks.to_json %></script>

    <script src="https://cdn.jsdelivr.net/npm/frappe-gantt@1.2.2/dist/frappe-gantt.umd.js"></script>
    <script>
      function toDateInputValue(date) {
        var year = date.getFullYear();
        var month = String(date.getMonth() + 1).padStart(2, "0");
        var day = String(date.getDate()).padStart(2, "0");
        return year + "-" + month + "-" + day;
      }

      document.addEventListener("DOMContentLoaded", function () {
        var tasks = JSON.parse(document.getElementById("gantt-tasks").textContent);
        if (tasks.length === 0) return;

        function saveStage(stageId, attrs) {
          fetch("<%= project_path(@project) %>", {
            method: "PATCH",
            headers: {
              "Content-Type": "application/json",
              "Accept": "application/json",
              "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
            },
            body: JSON.stringify({
              project: { project_stages_attributes: { "0": Object.assign({ id: stageId }, attrs) } }
            })
          })
            .then(function (response) {
              if (!response.ok) throw new Error("save failed");
              return response.json();
            })
            .then(function (stages) {
              var updated = stages.find(function (s) { return String(s.id) === String(stageId); });
              if (!updated) return;
              var row = document.getElementById("stage-" + stageId);
              row.querySelector("input[name*='[start_date]']").value = updated.start_date || "";
              row.querySelector("input[name*='[end_date]']").value = updated.end_date || "";
              row.querySelector("input[name*='[progress_percent]']").value = updated.progress_percent;
            })
            .catch(function () {
              gantt.refresh(tasks);
              alert("No se pudo guardar el cambio. Intenta de nuevo.");
            });
        }

        var gantt = new Gantt("#gantt", tasks, {
          language: "es",
          popup: false,
          today_button: false,
          container_height: 630,
          view_mode_select: false
        });
        gantt.on("click", function (task) { window.location.hash = "stage-" + task.id; });
        gantt.on("date_change", function (task, start, end) {
          saveStage(task.id, { start_date: toDateInputValue(start), end_date: toDateInputValue(end) });
        });
        gantt.on("progress_change", function (task, progress) {
          saveStage(task.id, { progress_percent: Math.round(progress) });
        });

        document.querySelectorAll("#view-mode-show .view-mode-btn").forEach(function (btn) {
          btn.addEventListener("click", function () {
            gantt.change_view_mode(btn.dataset.mode);
            document.querySelectorAll("#view-mode-show .view-mode-btn").forEach(function (b) { b.classList.remove("active"); });
            btn.classList.add("active");
          });
        });
      });
    </script>
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: all PASS.

- [ ] **Step 6: Run the full suite to check for regressions elsewhere**

Run: `bin/rails test`
Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add app/views/projects/show.html.erb test/controllers/projects_controller_test.rb
git commit -m "Upgrade the editable projects#show Gantt to frappe-gantt 1.2.2"
```

---

## Final Verification

- [ ] Run the full test suite: `bin/rails test`
- [ ] Expected: all tests pass, no regressions anywhere else in the app.
- [ ] Manual check recommended (not verifiable via integration test without a real browser, consistent with prior JS-behavior work in this app): open `/projects`, confirm the date header stays visible while scrolling a section with 15+ projects, and that the Día/Semana/Mes buttons change the visible range. Open a project's detail page, confirm dragging a bar still saves via fetch, and that Día/Semana/Mes work there too.
