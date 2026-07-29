# TomSelect en los selects grandes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add TomSelect (search-as-you-type) to the app's large-catalog `<select>`s (Responsable, Proyecto, Usuario vinculado), loaded via CDN like every other third-party JS in this app — leave small fixed-option selects (Estado, Tipo de responsable, Tipo de asociación) as native `<select>`.

**Architecture:** TomSelect CSS/JS loaded globally in the layout, plus one generic init script that upgrades any `<select class="js-tomselect">` found on the page. The one select with existing custom JS (the "Proyecto" dropdown that depends on "Tipo de asociación", from a prior task) gets its own self-contained TomSelect init inside that same script, so it works regardless of script execution order relative to the generic layout-level init.

**Tech Stack:** Rails 7.2, Minitest with fixtures, TomSelect 2.3.1 via jsdelivr CDN (no bundler — this app has no importmap/webpacker actually wired up despite the gem being in the Gemfile; CDN `<script src>` is the established pattern here, same as Bootstrap/frappe-gantt/trix).

## Global Constraints

- No DB/model/logic changes. No JS bundler introduced — CDN only, matching existing conventions.
- Only these six selects gain `class="js-tomselect"` (in addition to their existing `form-select` class): the "Responsable" filter and bulk-assign selects in `_project_type_section.html.erb`, the "Responsable" filter in `tracker.html.erb`, the "Responsable" assignment select in `projects/show.html.erb`'s Responsables card, the "Proyecto" select in `projects/show.html.erb`'s Asociaciones card, and "Usuario vinculado" in `admin/responsibles/_form.html.erb`. No other select changes.
- There is no automated way to test TomSelect's actual JS behavior in this app's Minitest suite (same limitation as the existing Gantt/drag-reorder JS) — tests here only confirm the right elements carry the right class/markup; real interaction needs a manual browser check afterward.

---

### Task 1: Load TomSelect and upgrade the five simple selects

**Files:**
- Modify: `app/views/layouts/application.html.erb`
- Modify: `app/views/projects/_project_type_section.html.erb`
- Modify: `app/views/projects/tracker.html.erb`
- Modify: `app/views/projects/show.html.erb`
- Modify: `app/views/admin/responsibles/_form.html.erb`
- Test: `test/controllers/projects_controller_test.rb`
- Test: `test/controllers/admin/responsibles_controller_test.rb`

**Interfaces:**
- None — pure view/CSS/JS change.

- [ ] **Step 1: Write the failing tests**

Add to `test/controllers/projects_controller_test.rb`:

```ruby
  test "index's Responsable filter select is marked for TomSelect" do
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_type_projects_path(project_types(:instalaciones).slug)
    assert_response :success
    assert_select "select.js-tomselect[name=?]", "responsible_id"
  end

  test "index's bulk-assign Responsable select is marked for TomSelect" do
    slug = project_types(:instalaciones).slug
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_type_projects_path(slug)
    assert_response :success
    assert_select "select#bulk-assign-responsible-select-#{slug}.js-tomselect"
  end

  test "show's Asociaciones Tipo de asociación select stays a plain native select" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_path(project)
    assert_response :success
    assert_select "select#project_association_project_type_association_id.js-tomselect", count: 0
  end

  test "tracker's Responsable filter select is marked for TomSelect" do
    get tracker_projects_path
    assert_response :success
    assert_select "select.js-tomselect[name=?]", "responsible_id"
  end

  test "show's Responsables assignment select is marked for TomSelect" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_path(project)
    assert_response :success
    assert_select "select.js-tomselect#project_responsible_responsible_id"
  end
```

Add to `test/controllers/admin/responsibles_controller_test.rb`:

```ruby
  test "new shows the Usuario vinculado select marked for TomSelect" do
    get new_admin_responsible_path
    assert_response :success
    assert_select "select.js-tomselect#responsible_user_id"
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/controllers/projects_controller_test.rb test/controllers/admin/responsibles_controller_test.rb -n "/TomSelect/"`
Expected: FAIL — none of the selects have the `js-tomselect` class yet.

- [ ] **Step 3: Load TomSelect and add the generic init script**

In `app/views/layouts/application.html.erb`, add this line right after the Bootstrap Icons `<link>`:

```erb
    <link href="https://cdn.jsdelivr.net/npm/tom-select@2.3.1/dist/css/tom-select.bootstrap5.min.css" rel="stylesheet">
```

Add this line right after the Bootstrap `<script>` tag near `</body>`:

```erb
    <script src="https://cdn.jsdelivr.net/npm/tom-select@2.3.1/dist/js/tom-select.complete.min.js"></script>
    <script>
      document.addEventListener("DOMContentLoaded", function () {
        document.querySelectorAll("select.js-tomselect").forEach(function (el) {
          if (!el.tomselect) new TomSelect(el, { create: false, allowEmptyOption: true });
        });
      });
    </script>
```

- [ ] **Step 4: Mark the "Responsable" filter and bulk-assign selects in `_project_type_section.html.erb`**

Find:

```erb
      <%= form.select :responsible_id,
            [["Sin asignar", "none"]] + Responsible.joins(:project_responsibles).where(project_responsibles: { responsible_type_id: section_params[:responsible_type_id] }).distinct.order(:name).collect { |r| [r.name, r.id] },
            { include_blank: "Todos", selected: section_params[:responsible_id] }, class: "form-select" %>
```

Change `class: "form-select"` to `class: "form-select js-tomselect"`.

Find:

```erb
        <%= f.select :responsible_id, project_type.responsibles.order(:name).collect { |r| [r.name, r.id] },
              { include_blank: "Elegí un responsable" }, class: "form-select", id: "bulk-assign-responsible-select-#{slug}" %>
```

Change `class: "form-select"` to `class: "form-select js-tomselect"`.

- [ ] **Step 5: Mark the "Responsable" filter select in `tracker.html.erb`**

Find:

```erb
    <%= form.select :responsible_id,
          [["Sin asignar", "none"]] + Responsible.joins(:project_responsibles).where(project_responsibles: { responsible_type_id: params[:responsible_type_id] }).distinct.collect { |r| [r.name, r.id] },
          { include_blank: "Todos", selected: params[:responsible_id] }, class: "form-select" %>
```

Change `class: "form-select"` to `class: "form-select js-tomselect"`.

- [ ] **Step 6: Mark the "Responsable" assignment select in `projects/show.html.erb`'s Responsables card**

Find:

```erb
            <%= form.collection_select :responsible_id, @project.project_type.responsibles.order(:name), :id, :name, { include_blank: "Responsable" }, class: "form-select" %>
```

Change `class: "form-select"` to `class: "form-select js-tomselect"`.

- [ ] **Step 7: Mark "Usuario vinculado" in `admin/responsibles/_form.html.erb`**

Find:

```erb
      <%= form.collection_select :user_id, unlinked_users, :id, :email, { include_blank: "Ninguno" }, class: "form-select" %>
```

Change `class: "form-select"` to `class: "form-select js-tomselect"`.

- [ ] **Step 8: Run tests to verify they pass**

Run: `bin/rails test test/controllers/projects_controller_test.rb test/controllers/admin/responsibles_controller_test.rb`
Expected: PASS

- [ ] **Step 9: Run the full suite**

Run: `bin/rails test`
Expected: PASS, no regressions.

- [ ] **Step 10: Commit**

```bash
git add app/views/layouts/application.html.erb app/views/projects/_project_type_section.html.erb \
  app/views/projects/tracker.html.erb app/views/projects/show.html.erb \
  app/views/admin/responsibles/_form.html.erb test/controllers/projects_controller_test.rb \
  test/controllers/admin/responsibles_controller_test.rb
git commit -m "Add TomSelect to the app's large-catalog dropdowns"
```

---

### Task 2: Reconcile TomSelect with the dependent "Proyecto" select

**Files:**
- Modify: `app/views/projects/show.html.erb`
- Test: `test/controllers/projects_controller_test.rb`

**Interfaces:**
- Consumes: the `js-tomselect` convention and generic init script from Task 1.

The "Proyecto" select in the Asociaciones card already has a custom filtering script (from a prior task) that hides/shows native `<option>` elements based on the chosen "Tipo de asociación". TomSelect wraps the underlying `<select>` in its own widget, so hiding native `<option>`s no longer has any visible effect — the script needs to drive TomSelect's own option list instead (`clearOptions`/`addOption`/`refreshOptions`).

**Important ordering note:** this script is embedded inside the view (`show.html.erb`), which renders *before* Task 1's generic init script (that one lives in the layout, near `</body>`, after `yield`). Script tags register their `DOMContentLoaded` listeners in document order, so this view's script would run *first* — meaning `otherSelect.tomselect` would not exist yet if this script merely checked for it and bailed. To avoid depending on execution order, this script initializes TomSelect on the "Proyecto" select itself (guarded by `if (!otherSelect.tomselect)`, so if the generic script happens to run first in some future refactor, this is still a no-op the second time, not a double-init).

- [ ] **Step 1: Write the failing test**

Add to `test/controllers/projects_controller_test.rb`:

```ruby
  test "show's Asociaciones Proyecto select is marked for TomSelect" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_path(project)
    assert_response :success
    assert_select "select.js-tomselect#project_association_other_project_id"
  end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n "/Asociaciones Proyecto select is marked/"`
Expected: FAIL — the select doesn't have the `js-tomselect` class yet.

- [ ] **Step 3: Mark the select and replace the filtering script**

Read the current `app/views/projects/show.html.erb` first — find the Asociaciones card's "Proyecto" `f.select` and the `<script>` block right after the form (from the prior task). Change the select's class from `class: "form-select"` to `class: "form-select js-tomselect"`:

```erb
            <%= f.select :other_project_id, options_for_select(project_options),
                  { include_blank: "Proyecto" }, class: "form-select js-tomselect", id: "project_association_other_project_id" %>
```

Replace the entire existing `<script>` block (the one starting with `document.addEventListener("DOMContentLoaded", function () { var typeSelect = ...`) with:

```erb
        <script>
          document.addEventListener("DOMContentLoaded", function () {
            var typeSelect = document.getElementById("project_association_project_type_association_id");
            var otherSelect = document.getElementById("project_association_other_project_id");
            if (!typeSelect || !otherSelect) return;
            if (!otherSelect.tomselect) new TomSelect(otherSelect, { create: false, allowEmptyOption: true });

            var allProjectOptions = Array.from(otherSelect.options)
              .filter(function (o) { return o.value; })
              .map(function (o) { return { value: o.value, text: o.text, projectTypeId: o.dataset.projectTypeId }; });

            function filterProjects() {
              var selectedValue = typeSelect.value;
              var selectedOption = selectedValue ? typeSelect.querySelector('option[value="' + selectedValue + '"]') : null;
              var otherProjectTypeId = selectedOption ? selectedOption.dataset.otherProjectTypeId : null;

              var ts = otherSelect.tomselect;
              ts.clear();
              ts.clearOptions();
              allProjectOptions
                .filter(function (o) { return !otherProjectTypeId || o.projectTypeId === otherProjectTypeId; })
                .forEach(function (o) { ts.addOption(o); });
              ts.refreshOptions(false);
            }

            typeSelect.addEventListener("change", filterProjects);
            filterProjects();
          });
        </script>
```

(`allProjectOptions` is read from `otherSelect.options` *before* TomSelect finishes wrapping it — this still works because the constructor call and the `Array.from(otherSelect.options)` read both happen synchronously, in order, within the same script execution, before TomSelect has a chance to hide/replace anything asynchronously.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: PASS

- [ ] **Step 5: Run the full suite**

Run: `bin/rails test`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add app/views/projects/show.html.erb test/controllers/projects_controller_test.rb
git commit -m "Make the dependent Proyecto select work through TomSelect"
```

---

## Manual verification (not automatable)

After both tasks land, check in an actual browser (per the spec's Edge cases section):
- Each of the six selects shows a searchable TomSelect widget instead of a native dropdown.
- Typing in "Responsable"/"Proyecto"/"Usuario vinculado" narrows the list as expected.
- In the Asociaciones card, choosing a "Tipo de asociación" still correctly narrows "Proyecto"'s TomSelect options to the matching type, and submitting the form still sends the right `other_project_id`.
