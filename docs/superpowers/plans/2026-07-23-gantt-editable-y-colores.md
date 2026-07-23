# Gantt editable por arrastre en el detalle de proyecto, fix de colores — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix a real CSS specificity bug that reverts Gantt bars to the library's default color on hover/click, and let dragging a bar on the project detail page persist the change (dates + progress) with the stage table syncing itself — without making the aggregate home-screen Gantt draggable.

**Architecture:** Task 1 is a pure CSS selector fix in two view files. Task 2 adds a JSON response branch to the existing `ProjectsController#update` (no new route/controller) and replaces the read-only snap-back JS in `projects/show.html.erb` with a `fetch`-based save that updates the DOM on success and snaps back on failure.

**Tech Stack:** Ruby on Rails, Minitest, frappe-gantt 0.6.1 (CDN, unchanged), vanilla JS (`fetch`) — no new JS dependency, no Turbo/Stimulus (confirmed not wired into the layout).

## Global Constraints

- No new gems, no new routes, no new controller.
- No `!important` in CSS — match or exceed the competing selector's specificity instead (see Task 1).
- The home-screen Gantt (`projects/index.html.erb`) stays read-only — only its color CSS changes in this plan, not its drag behavior.
- Date values passed to `on_date_change`/`on_progress_change` are native JS `Date` objects (confirmed by reading the frappe-gantt source) — format them using local date components (`getFullYear`/`getMonth`/`getDate`), never `toISOString()`, which can shift the date by one day depending on the browser's timezone offset.

---

### Task 1: Fix Gantt bar color specificity (both views)

**Files:**
- Modify: `app/views/projects/index.html.erb` (color `<style>` block)
- Modify: `app/views/projects/show.html.erb` (color `<style>` block)
- Modify: `test/controllers/projects_controller_test.rb` (update one existing test, add one new test)

**Interfaces:**
- Consumes: `StageTemplate#color` (unchanged), `Project#current_stage` (unchanged, used by `index.html.erb`).
- Produces: nothing consumed by Task 2 — Task 2 touches the JS/controller, not the CSS selectors.

- [ ] **Step 1: Update the failing test for `show`**

Edit `test/controllers/projects_controller_test.rb` — replace this test:

```ruby
  test "show colors each stage's Gantt bar by its stage_template's color" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    stage_templates(:produccion).update!(color: "#ff0000")

    get project_path(project)
    assert_response :success
    assert_match(
      /\.bar-wrapper\.stage-color-#{stage_templates(:produccion).id}\s*\.bar\s*\{\s*fill:\s*#ff0000;?\s*\}/,
      response.body
    )
  end
```

with:

```ruby
  test "show colors each stage's Gantt bar by its stage_template's color, including hover/active states" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    stage_templates(:produccion).update!(color: "#ff0000")
    id = stage_templates(:produccion).id

    get project_path(project)
    assert_response :success
    assert_match(/\.gantt \.bar-wrapper\.stage-color-#{id} \.bar,/, response.body)
    assert_match(/\.gantt \.bar-wrapper\.stage-color-#{id}:hover \.bar,/, response.body)
    assert_match(/\.gantt \.bar-wrapper\.stage-color-#{id}\.active \.bar \{\s*fill:\s*#ff0000;?\s*\}/, response.body)
  end
```

- [ ] **Step 2: Add the new test for `index`**

Add to `test/controllers/projects_controller_test.rb`, inside the existing test class:

```ruby
  test "index colors each project's Gantt bar including hover/active states" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    stage_templates(:diseno_aprobacion).update!(color: "#00ff00")
    id = stage_templates(:diseno_aprobacion).id

    get projects_path
    assert_response :success
    assert_match(/\.gantt \.bar-wrapper\.stage-color-#{id} \.bar,/, response.body)
    assert_match(/\.gantt \.bar-wrapper\.stage-color-#{id}:hover \.bar,/, response.body)
    assert_match(/\.gantt \.bar-wrapper\.stage-color-#{id}\.active \.bar \{\s*fill:\s*#00ff00;?\s*\}/, response.body)
  end
```

(Uses `diseno_aprobacion` — the first stage template by position — because `Project#current_stage` returns the first stage when none has started, per `app/models/project.rb`'s existing behavior; a freshly created project's current stage is its first one.)

- [ ] **Step 3: Run the tests to verify they fail**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: FAIL — the current CSS only has the base `.bar-wrapper.stage-color-N .bar` rule, no `:hover`/`.active` variants, and no `.gantt` prefix.

- [ ] **Step 4: Fix the CSS in `show.html.erb`**

Edit `app/views/projects/show.html.erb` — replace:

```erb
    <style>
      <% stage_colors.each do |template_id, color| %>
        .bar-wrapper.stage-color-<%= template_id %> .bar { fill: <%= color %>; }
      <% end %>
    </style>
```

with:

```erb
    <style>
      <% stage_colors.each do |template_id, color| %>
        .gantt .bar-wrapper.stage-color-<%= template_id %> .bar,
        .gantt .bar-wrapper.stage-color-<%= template_id %>:hover .bar,
        .gantt .bar-wrapper.stage-color-<%= template_id %>.active .bar {
          fill: <%= color %>;
        }
      <% end %>
    </style>
```

- [ ] **Step 5: Fix the CSS in `index.html.erb`**

Edit `app/views/projects/index.html.erb` — replace:

```erb
  <style>
    <% gantt_colors.each do |template_id, color| %>
      .bar-wrapper.stage-color-<%= template_id %> .bar { fill: <%= color %>; }
    <% end %>
  </style>
```

with:

```erb
  <style>
    <% gantt_colors.each do |template_id, color| %>
      .gantt .bar-wrapper.stage-color-<%= template_id %> .bar,
      .gantt .bar-wrapper.stage-color-<%= template_id %>:hover .bar,
      .gantt .bar-wrapper.stage-color-<%= template_id %>.active .bar {
        fill: <%= color %>;
      }
    <% end %>
  </style>
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: PASS (all tests)

- [ ] **Step 7: Run the full suite**

Run: `bin/rails test`
Expected: PASS

- [ ] **Step 8: Manual verification**

Run: `bin/rails server`, open a project's detail page and the home screen, hover over and click a Gantt bar on each, confirm the configured `StageTemplate#color` stays visible instead of reverting to the library's default gray-blue.

- [ ] **Step 9: Commit**

```bash
git add app/views/projects/index.html.erb app/views/projects/show.html.erb test/controllers/projects_controller_test.rb
git commit -m "Fix Gantt bar color reverting on hover/click (CSS specificity)"
```

---

### Task 2: Drag-to-save on the project detail Gantt

**Files:**
- Modify: `app/controllers/projects_controller.rb` (`update` action, add `stage_payload`)
- Modify: `app/views/projects/show.html.erb` (Gantt `<script>` block)
- Modify: `test/controllers/projects_controller_test.rb` (add 3 tests)

**Interfaces:**
- Consumes: `Project#project_stages` / `accepts_nested_attributes_for :project_stages` (unchanged, from an earlier round), `project_params` (unchanged — already permits `project_stages_attributes`).
- Produces: `ProjectsController#update` now also responds to `format.json` — no later task in this plan depends on it (this is the last task).

- [ ] **Step 1: Write the failing controller tests**

Add to `test/controllers/projects_controller_test.rb`, inside the existing test class:

```ruby
  test "update responds with JSON stage data when Accept is application/json" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    stage = project.project_stages.order(:id).first

    patch project_path(project), params: {
      project: {
        project_stages_attributes: { "0" => { id: stage.id, start_date: "2026-08-01", end_date: "2026-08-10", progress_percent: 60 } }
      }
    }, as: :json

    assert_response :success
    body = JSON.parse(response.body)
    updated = body.find { |s| s["id"] == stage.id }
    assert_equal "2026-08-01", updated["start_date"]
    assert_equal "2026-08-10", updated["end_date"]
    assert_equal 60, updated["progress_percent"]
  end

  test "update with invalid data returns a 422 JSON error when Accept is application/json" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    stage = project.project_stages.order(:id).first

    patch project_path(project), params: {
      project: {
        project_stages_attributes: { "0" => { id: stage.id, progress_percent: 150 } }
      }
    }, as: :json

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert body["errors"].any?
  end

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

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: FAIL — `update` doesn't respond to JSON yet, and `show.html.erb`'s script still has the old read-only snap-back callbacks.

- [ ] **Step 3: Add the JSON response to `ProjectsController#update`**

Edit `app/controllers/projects_controller.rb` — replace:

```ruby
  def update
    @project_type = @project.project_type
    if @project.update(project_params)
      redirect_to project_path(@project)
    else
      render :edit, status: :unprocessable_entity
    end
  end
```

with:

```ruby
  def update
    @project_type = @project.project_type
    if @project.update(project_params)
      respond_to do |format|
        format.html { redirect_to project_path(@project) }
        format.json { render json: stage_payload }
      end
    else
      respond_to do |format|
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: { errors: @project.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end
```

Add this private method, right after `project_params`:

```ruby
  def stage_payload
    @project.project_stages.map do |stage|
      { id: stage.id, start_date: stage.start_date, end_date: stage.end_date, progress_percent: stage.progress_percent }
    end
  end
```

- [ ] **Step 4: Run the controller tests to verify Step 1's first two tests pass**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n "/update responds with JSON|update with invalid data/"`
Expected: PASS

- [ ] **Step 5: Replace the Gantt `<script>` block in `show.html.erb`**

Replace:

```erb
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
```

with:

```erb
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

(The `if (tasks.length === 0) return;` early-return replaces the old `if (tasks.length > 0) { ... }` wrapper — same behavior, avoids re-indenting the entire block. `gantt` is declared with `var` inside the `DOMContentLoaded` handler, same scope as `saveStage`, so the `catch` callback can reference it.)

- [ ] **Step 6: Run the tests to verify they pass**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: PASS (all tests, including the 3rd new test from Step 1)

- [ ] **Step 7: Run the full suite**

Run: `bin/rails test`
Expected: PASS

- [ ] **Step 8: Manual verification**

Run: `bin/rails server`, open a project's detail page:
- Drag a Gantt bar to new dates — confirm the corresponding row in the stage table below updates its Inicio/Fin inputs without a page reload.
- Drag a bar's progress indicator — confirm the row's "% Avance" input updates.
- Reload the page — confirm the new dates/progress persisted (came from the database, not just the DOM).
- With the browser's dev tools set to offline/network-blocked, drag a bar — confirm it snaps back to its original position and an alert appears, instead of silently losing the change.

- [ ] **Step 9: Commit**

```bash
git add app/controllers/projects_controller.rb app/views/projects/show.html.erb test/controllers/projects_controller_test.rb
git commit -m "Let dragging a bar on the project detail Gantt save via AJAX, syncing the stage table"
```

---

## Final verification

- [ ] Run `bin/rails test` once more — expect a clean pass.
- [ ] Manually confirm the home-screen Gantt (`/projects`) is still NOT draggable (dragging a project bar there should still snap back, per Round 1 — this plan does not touch its drag behavior, only its color CSS).
