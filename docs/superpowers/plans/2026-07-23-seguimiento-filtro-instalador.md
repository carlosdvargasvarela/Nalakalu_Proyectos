# Filtro por instalador en Seguimiento — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an installer filter to "Seguimiento", mirroring the one already on the home screen.

**Architecture:** Reuses `ProjectsController#filter_by_installer` exactly as it exists today (no changes to that method) — only `tracker`'s action body and its view gain a third filter control.

**Tech Stack:** Ruby on Rails, Minitest.

## Global Constraints

- `filter_by_installer` (private method in `ProjectsController`) is not modified in any way — it's already correct and tested via `index`.
- No route/model changes.

---

### Task 1: Installer filter on Seguimiento

**Files:**
- Modify: `app/controllers/projects_controller.rb` (`tracker` action only)
- Modify: `app/views/projects/tracker.html.erb`
- Modify: `test/controllers/projects_controller_test.rb`

**Interfaces:**
- Consumes: `ProjectsController#filter_by_installer(scope, installer_id)` (unchanged, private, already exists).
- Produces: nothing consumed by a later task — this is the only task in this plan.

- [ ] **Step 1: Write the failing tests**

Add to `test/controllers/projects_controller_test.rb`, inside the existing test class:

```ruby
  test "tracker filters by installer" do
    otro_instalador = Installer.create!(name: "Otro Instalador")
    con_juan = Project.create!(
      project_type: project_types(:instalaciones), name: "Con Juan",
      custom_fields: { instalador: installers(:juan_perez).id }
    )
    con_otro = Project.create!(
      project_type: project_types(:instalaciones), name: "Con Otro",
      custom_fields: { instalador: otro_instalador.id }
    )

    get tracker_projects_path, params: { installer_id: installers(:juan_perez).id }
    assert_response :success
    assert_match(/#{con_juan.name}/, response.body)
    assert_no_match(/#{con_otro.name}/, response.body)
  end

  test "tracker without installer_id still shows every project of the type" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get tracker_projects_path
    assert_response :success
    assert_match(/#{project.name}/, response.body)
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: FAIL — `tracker` doesn't accept `installer_id` yet, so both projects show regardless of the filter (first test fails; second test already passes today but confirm it still does after Step 2's run, since it's a pre-existing-equivalent behavior, not a new one).

- [ ] **Step 3: Update the controller**

Edit `app/controllers/projects_controller.rb` — replace the `tracker` method:

```ruby
  def tracker
    @project_types = ProjectType.all
    @installers = Installer.all
    @project_type = ProjectType.find_by(id: params[:project_type_id]) || ProjectType.first
    @projects = if @project_type
      scope = Project.where(project_type: @project_type).where.not(status: "archived")
                     .includes(project_stages: :stage_template).order(:name)
      params[:installer_id].present? ? filter_by_installer(scope, params[:installer_id]) : scope
    else
      Project.none
    end
  end
```

- [ ] **Step 4: Add the filter control to the view**

Edit `app/views/projects/tracker.html.erb` — inside the `form_with` block, add after the "Tipo" `<div class="col-auto">`:

```erb
  <div class="col-auto">
    <%= form.label :installer_id, "Instalador", class: "form-label" %>
    <%= form.select :installer_id, @installers.collect { |i| [i.name, i.id] },
          { include_blank: "Todos", selected: params[:installer_id] }, class: "form-select" %>
  </div>
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: PASS (all tests)

- [ ] **Step 6: Run the full suite**

Run: `bin/rails test`
Expected: PASS

- [ ] **Step 7: Manual verification**

Run: `bin/rails server`, go to "Seguimiento":
- Confirm the "Instalador" dropdown appears next to "Tipo".
- Select an installer with at least one assigned project — confirm only matching projects show.
- Clear the filter ("Todos") — confirm all projects of the type show again.

- [ ] **Step 8: Commit**

```bash
git add app/controllers/projects_controller.rb app/views/projects/tracker.html.erb \
  test/controllers/projects_controller_test.rb
git commit -m "Add installer filter to Seguimiento"
```

---

## Final verification

- [ ] Run `bin/rails test` once more — expect a clean pass.
