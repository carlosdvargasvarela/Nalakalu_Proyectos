# Pending Panel Stage Filter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When the "Etapa" filter is active on the project-list page, the "Pendientes de fecha" panel shows a project only if that specific filtered stage lacks a date — not any stage.

**Architecture:** One `filter_map` in `_project_type_section.html.erb` gets a branch: when `section[:stage_name]` is present, look up that one stage per project and check only its `dates_missing?`; when absent, keep the exact current logic (`stages_missing_dates` + `pending_auto_duration_start_date?`).

**Tech Stack:** Rails 7.2 (ERB), Minitest.

## Global Constraints

- Zero behavior change when no "Etapa" filter is active — every existing "Pendientes de fecha" test must keep passing unmodified.
- The "Calcular" button (auto-duration) keeps being driven by `Project#pending_auto_duration_start_date?` regardless of the stage filter — it acts on the whole project's chain starting from stage 1, not on the filtered stage.
- A project that doesn't have a stage matching the filtered name is excluded from the panel (same rule already used for the Gantt in the same file).

---

### Task 1: Scope the pending panel to the active stage filter

**Files:**
- Modify: `app/views/projects/_project_type_section.html.erb:130-161`
- Test: `test/controllers/projects_controller_test.rb`

**Interfaces:**
- Consumes: `ProjectStage#dates_missing?` (existing), `Project#stages_missing_dates`, `Project#pending_auto_duration_start_date?` (existing, unchanged signatures).
- Produces: no new interface — last task of this plan.

- [ ] **Step 1: Write the failing tests**

Add to `test/controllers/projects_controller_test.rb`, right after the test `"index hides the pendientes de fecha panel when every stage has dates"` (around line 657-666):

```ruby
  test "index's pendientes de fecha panel, with a stage filter active, shows a project only if THAT stage lacks a date" do
    project_types(:instalaciones).update!(require_stage_dates: true)
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    project.project_stages.where.not(name: "Instalación").each { |stage| stage.update!(start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 1, 10)) }
    slug = project_types(:instalaciones).slug

    get project_type_projects_path(slug), params: { stage_name: "Instalación", status: "" }
    assert_response :success
    assert_select ".card-header", "Pendientes de fecha"
    assert_select "body", /Torre Norte/
  end

  test "index's pendientes de fecha panel, with a stage filter active, hides a project whose filtered stage already has a date" do
    project_types(:instalaciones).update!(require_stage_dates: true)
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    instalacion = project.project_stages.find_by(name: "Instalación")
    instalacion.update!(start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 1, 10))
    # every OTHER stage stays undated on purpose
    slug = project_types(:instalaciones).slug

    get project_type_projects_path(slug), params: { stage_name: "Instalación", status: "" }
    assert_response :success
    assert_select ".card-header", text: "Pendientes de fecha", count: 0
  end
```

- [ ] **Step 2: Run to confirm they fail**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n "/pendientes de fecha panel, with a stage filter active/"`
Expected: the second test ("hides a project whose filtered stage already has a date") FAILS — today the panel ignores the filter entirely, so it still shows the project because its other stages are undated. The first test may already pass by coincidence (the project genuinely has a missing stage), but re-run both together after Step 4 regardless.

- [ ] **Step 3: Update the pending-panel logic**

In `app/views/projects/_project_type_section.html.erb`, replace the `pending_projects = projects_list.filter_map do |project| ... end` block (currently lines 132-136, inside the `<% if project_type.require_stage_dates? || project_type.auto_stage_duration_enabled? %>` block):

```erb
    <%
      pending_projects = projects_list.filter_map do |project|
        if section[:stage_name].present?
          stage = project.project_stages.find { |s| s.name == section[:stage_name] }
          next if stage.nil? || !stage.dates_missing?
          [project, [stage], project.pending_auto_duration_start_date?]
        else
          missing = project.stages_missing_dates
          needs_start = project.pending_auto_duration_start_date?
          [project, missing, needs_start] if missing.any? || needs_start
        end
      end
    %>
```

(Only this Ruby block changes — the surrounding `<% if %>` / `<% if pending_projects.any? %>` / the `<ul>` rendering loop below it are untouched.)

- [ ] **Step 4: Run the new tests to confirm they pass**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n "/pendientes de fecha panel, with a stage filter active/"`
Expected: both PASS

- [ ] **Step 5: Run the full controller test file**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: all PASS, 0 failures — in particular every pre-existing "Pendientes de fecha" test (lines 589-666: require_stage_dates panel, auto-duration panel, hidden-when-off, hidden-when-all-dated) must still pass unmodified, since none of them pass a `stage_name` param and therefore exercise the unchanged `else` branch.

- [ ] **Step 6: Run the full test suite**

Run: `bin/rails test`
Expected: all PASS, 0 failures.

- [ ] **Step 7: Commit**

```bash
git add app/views/projects/_project_type_section.html.erb test/controllers/projects_controller_test.rb
git commit -m "Acotar el panel de pendientes de fecha a la etapa filtrada, cuando hay filtro activo"
```
