# Color por instalador en el Gantt general — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `color` field to `Installer` (admin-editable, same pattern as `StageTemplate#color`) and switch the home-screen Gantt's bar coloring from "current stage" to "assigned installer" — with a neutral gray fallback for projects that don't have one assigned yet.

**Architecture:** Three sequential tasks: (1) the `Installer#color` column/validation/admin form, mirroring `StageTemplate#color` exactly, (2) a `Project#installer` model method that resolves the assigned installer through the dynamic `custom_fields`/`FieldDefinition` mechanism (no hardcoded field key), (3) `projects/index.html.erb` switches its Gantt coloring to use it, with the CSS specificity fix (from the prior round) applied from the start.

**Tech Stack:** Ruby on Rails, Minitest + fixtures, frappe-gantt 0.6.1 (CDN, unchanged — only the color CSS/data changes, not the library usage).

## Global Constraints

- No new gems.
- Every new strong-params permit list must explicitly include `:color` where relevant — the prior round shipped `StageTemplate#color` without permitting it in the controller, silently dropping every save. Task 1 permits `:color` in `Admin::InstallersController` as part of the same commit that adds the column, with a test that would have caught that exact bug.
- The project detail Gantt (`projects/show.html.erb`) is NOT touched by this plan — it keeps coloring by `StageTemplate#color`, unchanged.
- New CSS must use the specificity-safe selector shape already established in the prior round: `.gantt .bar-wrapper.X .bar, .gantt .bar-wrapper.X:hover .bar, .gantt .bar-wrapper.X.active .bar` — never the bare 3-class form that reverts color on hover/click.

---

### Task 1: `Installer#color`

**Files:**
- Create: `db/migrate/20260723150000_add_color_to_installers.rb`
- Modify: `app/models/installer.rb`
- Modify: `app/controllers/admin/installers_controller.rb`
- Modify: `app/views/admin/installers/_form.html.erb`
- Modify: `test/models/installer_test.rb`
- Modify: `test/controllers/admin/installers_controller_test.rb`

**Interfaces:**
- Consumes: nothing new.
- Produces: `Installer#color` (String, default `"#6c757d"`, validated hex format) — consumed by Task 3's view. `installer_params` now permits `:color` — no other task depends on this directly, but Task 3's manual verification relies on being able to actually set a color through the admin UI.

- [ ] **Step 1: Write the failing model tests**

Add to `test/models/installer_test.rb`, inside the existing test class:

```ruby
  test "valid with default color" do
    installer = Installer.new(name: "Ana Gómez")
    assert installer.valid?
    assert_equal "#6c757d", installer.color
  end

  test "invalid with a malformed color" do
    installer = Installer.new(name: "Ana Gómez", color: "blue")
    assert_not installer.valid?
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/models/installer_test.rb`
Expected: FAIL — `NoMethodError: undefined method 'color'` (the column doesn't exist yet).

- [ ] **Step 3: Add the migration and run it**

Create `db/migrate/20260723150000_add_color_to_installers.rb`:

```ruby
class AddColorToInstallers < ActiveRecord::Migration[7.2]
  def change
    add_column :installers, :color, :string, null: false, default: "#6c757d"
  end
end
```

Run: `bin/rails db:migrate`
Expected: migration applies cleanly, `db/schema.rb` gains the `color` column on `installers` (same shape as `stage_templates.color`).

- [ ] **Step 4: Add the validation**

Edit `app/models/installer.rb`:

```ruby
class Installer < ApplicationRecord
  validates :name, presence: true
  validates :color, format: { with: /\A#[0-9a-fA-F]{6}\z/, message: "debe ser un color hexadecimal (ej. #6c757d)" }
end
```

- [ ] **Step 5: Run the model tests to verify they pass**

Run: `bin/rails test test/models/installer_test.rb`
Expected: PASS (4 tests)

- [ ] **Step 6: Write the failing controller test (the exact bug class from the prior round)**

Add to `test/controllers/admin/installers_controller_test.rb`, inside the existing test class:

```ruby
  test "update saves the color" do
    installer = installers(:juan_perez)
    patch admin_installer_path(installer), params: { installer: { name: installer.name, color: "#f60404" } }
    assert_redirected_to admin_installers_path
    assert_equal "#f60404", installer.reload.color
  end
```

- [ ] **Step 7: Run the test to verify it fails**

Run: `bin/rails test test/controllers/admin/installers_controller_test.rb`
Expected: FAIL — `installer.reload.color` is still `"#6c757d"` (strong params don't permit `:color` yet — this is the same bug class as the `StageTemplate` one, caught here before shipping instead of after).

- [ ] **Step 8: Permit `:color`**

Edit `app/controllers/admin/installers_controller.rb`:

```ruby
  def installer_params
    params.require(:installer).permit(:name, :color)
  end
```

- [ ] **Step 9: Add the color field to the admin form**

Edit `app/views/admin/installers/_form.html.erb` — add after the `:name` field block:

```erb
  <div class="mb-3">
    <%= form.label :color, class: "form-label" %>
    <%= form.color_field :color, class: "form-control form-control-color" %>
  </div>
```

- [ ] **Step 10: Run the tests to verify they pass**

Run: `bin/rails test test/models/installer_test.rb test/controllers/admin/installers_controller_test.rb`
Expected: PASS (all tests)

- [ ] **Step 11: Run the full suite**

Run: `bin/rails test`
Expected: PASS

- [ ] **Step 12: Commit**

```bash
git add db/migrate/20260723150000_add_color_to_installers.rb db/schema.rb app/models/installer.rb \
  app/controllers/admin/installers_controller.rb app/views/admin/installers/_form.html.erb \
  test/models/installer_test.rb test/controllers/admin/installers_controller_test.rb
git commit -m "Add Installer#color, admin-editable"
```

---

### Task 2: `Project#installer`

**Files:**
- Modify: `app/models/project.rb`
- Modify: `test/models/project_test.rb`

**Interfaces:**
- Consumes: `FieldDefinition#reference_table`/`#key` (unchanged), `Project#custom_fields` (unchanged), `Installer` (from Task 1, needs `Installer.find_by(id:)` to work — doesn't need `#color` specifically, so this task has no hard dependency on Task 1's migration, but Task 1 should land first per this plan's ordering to keep manual verification meaningful).
- Produces: `Project#installer` → `Installer` or `nil`. Consumed by Task 3's view.

- [ ] **Step 1: Write the failing model tests**

Add to `test/models/project_test.rb`, inside the existing test class:

```ruby
  test "installer resolves the assigned Installer through the dynamic reference field" do
    project = Project.create!(
      project_type: @project_type, name: "Torre Norte",
      custom_fields: { "instalador" => installers(:juan_perez).id }
    )
    assert_equal installers(:juan_perez), project.installer
  end

  test "installer is nil when no installer has been assigned yet" do
    project = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: {})
    assert_nil project.installer
  end

  test "installer is nil when the assigned id no longer exists" do
    project = Project.create!(
      project_type: @project_type, name: "Torre Norte",
      custom_fields: { "instalador" => 999_999 }
    )
    assert_nil project.installer
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/models/project_test.rb`
Expected: FAIL — `NoMethodError: undefined method 'installer'`.

- [ ] **Step 3: Implement the method**

Edit `app/models/project.rb` — add after `current_stage`:

```ruby
  def installer
    key = project_type.field_definitions.find_by(reference_table: "installers")&.key
    return nil if key.nil?

    installer_id = custom_fields[key]
    return nil if installer_id.blank?

    Installer.find_by(id: installer_id)
  end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bin/rails test test/models/project_test.rb`
Expected: PASS (all tests)

- [ ] **Step 5: Run the full suite**

Run: `bin/rails test`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add app/models/project.rb test/models/project_test.rb
git commit -m "Add Project#installer, resolved through the dynamic reference field"
```

---

### Task 3: Color the home-screen Gantt by installer

**Files:**
- Modify: `app/views/projects/index.html.erb`
- Modify: `test/controllers/projects_controller_test.rb`

**Interfaces:**
- Consumes: `Project#installer` (Task 2), `Installer#color` (Task 1).
- Produces: nothing consumed by a later task — this is the last task in the plan.

- [ ] **Step 1: Write the failing controller tests**

Add to `test/controllers/projects_controller_test.rb`, inside the existing test class:

```ruby
  test "index colors a project's Gantt bar by its assigned installer" do
    installer = installers(:juan_perez)
    installer.update!(color: "#00ff00")
    Project.create!(
      project_type: project_types(:instalaciones), name: "Torre Norte",
      custom_fields: { instalador: installer.id }
    )

    get projects_path
    assert_response :success
    assert_match(/\.gantt \.bar-wrapper\.installer-color-#{installer.id} \.bar,/, response.body)
    assert_match(/\.gantt \.bar-wrapper\.installer-color-#{installer.id}:hover \.bar,/, response.body)
    assert_match(/\.gantt \.bar-wrapper\.installer-color-#{installer.id}\.active \.bar \{\s*fill:\s*#00ff00;?\s*\}/, response.body)
  end

  test "index colors a project with no installer assigned yet using the default gray" do
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})

    get projects_path
    assert_response :success
    assert_match(/\.gantt \.bar-wrapper\.installer-color-none \.bar,/, response.body)
    assert_match(/\.gantt \.bar-wrapper\.installer-color-none\.active \.bar \{\s*fill:\s*#6c757d;?\s*\}/, response.body)
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: FAIL — the CSS still uses `stage-color-N` classes, keyed to `current_stage`, not `installer-color-N`.

- [ ] **Step 3: Switch the coloring logic**

Edit `app/views/projects/index.html.erb` — replace:

```erb
  <%
    gantt_tasks = @projects.map do |project|
      first, last = project.gantt_window
      current = project.current_stage
      progress_values = project.project_stages.map(&:progress_percent)
      average_progress = progress_values.any? ? (progress_values.sum / progress_values.size.to_f).round : 0
      {
        id: project.id.to_s,
        name: project.name,
        start: first.to_s,
        end: last.to_s,
        progress: average_progress,
        edit_url: project_path(project),
        custom_class: "stage-color-#{current&.stage_template_id || 'none'}"
      }
    end
    gantt_colors = @projects.map do |project|
      template_id = project.current_stage&.stage_template_id || "none"
      color = project.current_stage&.stage_template&.color || "#6c757d"
      [template_id, color]
    end.uniq
  %>
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

with:

```erb
  <%
    gantt_tasks = @projects.map do |project|
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
    gantt_colors = @projects.map do |project|
      installer = project.installer
      [installer&.id || "none", installer&.color || "#6c757d"]
    end.uniq
  %>
  <style>
    <% gantt_colors.each do |installer_id, color| %>
      .gantt .bar-wrapper.installer-color-<%= installer_id %> .bar,
      .gantt .bar-wrapper.installer-color-<%= installer_id %>:hover .bar,
      .gantt .bar-wrapper.installer-color-<%= installer_id %>.active .bar {
        fill: <%= color %>;
      }
    <% end %>
  </style>
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: PASS (all tests — this also confirms the earlier "show colors each stage's Gantt bar..." test for the *detail* page still passes unchanged, since that page's coloring wasn't touched)

- [ ] **Step 5: Run the full suite**

Run: `bin/rails test`
Expected: PASS

- [ ] **Step 6: Manual verification**

Run: `bin/rails server`:
- In Administración → Instaladores, set a distinct color on an installer.
- Assign that installer to a project (via the project's "Instalador" custom field, editable on `projects#new`/`#edit`).
- Visit `/projects` (home screen) — confirm that project's Gantt bar shows the installer's color, including on hover/click.
- Confirm a project with no installer assigned shows the default gray bar.
- Visit that project's detail page — confirm its Gantt still colors by stage template (unchanged).

- [ ] **Step 7: Commit**

```bash
git add app/views/projects/index.html.erb test/controllers/projects_controller_test.rb
git commit -m "Color the home-screen Gantt by assigned installer instead of current stage"
```

---

## Final verification

- [ ] Run `bin/rails test` once more — expect a clean pass.
- [ ] `grep -rn "stage-color" app/views/projects/index.html.erb` returns nothing (confirms the old stage-based coloring is fully gone from this view, not left half-referenced) — `app/views/projects/show.html.erb` still uses `stage-color-*` and should NOT be touched by this grep's expectations.
