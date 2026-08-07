# Gantt Omit Auto-Duration Pending Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The three Gantt placeholder-omission checks (individual project, list unfiltered, list stage-filtered) skip the 7-day placeholder for `auto_stage_duration_enabled` project types too, not just `require_stage_dates` ones — matching the condition the "Pendientes de fecha" panel already uses.

**Architecture:** Three existing boolean checks (`project_type.require_stage_dates?`) become `(project_type.require_stage_dates? || project_type.auto_stage_duration_enabled?)`. No new methods, no new files.

**Tech Stack:** Rails 7.2 (ERB), Minitest.

## Global Constraints

- Zero behavior change for project types with both flags off, or with only `require_stage_dates` on — every existing Gantt-omission test for `require_stage_dates` must keep passing unmodified.
- Zero behavior change to the "Pendientes de fecha" panel itself — only the Gantt omission conditions change.
- Same combined condition `(require_stage_dates? || auto_stage_duration_enabled?)` in all three spots — do not invent a different check per file.

---

### Task 1: Combine both flags in the three Gantt omission checks

**Files:**
- Modify: `app/views/projects/show.html.erb:34`
- Modify: `app/views/projects/_project_type_section.html.erb:92,97`
- Test: `test/controllers/projects_controller_test.rb`

**Interfaces:**
- Consumes: `ProjectType#require_stage_dates?`, `ProjectType#auto_stage_duration_enabled?` (both existing boolean columns, no changes).
- Produces: no new interface — last task of this plan.

- [ ] **Step 1: Write the failing tests**

Add to `test/controllers/projects_controller_test.rb`, right after the test `"show still applies the placeholder date for undated stages when the project type doesn't require dates"` (around line 319-327):

```ruby
  test "show omits stages without dates from the Gantt when the project type has auto duration enabled" do
    field = FieldDefinition.create!(project_type: project_types(:instalaciones), key: "cantidad", label: "Cantidad", data_type: "number", position: 10)
    project_types(:instalaciones).update!(auto_stage_duration_enabled: true, duration_reference_field_definition: field)
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: { cantidad: "10" })
    dated, undated = project.project_stages.order(:id).first(2)
    dated.update!(start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 1, 10))

    get project_path(project)
    assert_response :success
    tasks = json_data_attribute('[data-controller="gantt-stage-editor"]', "data-gantt-stage-editor-tasks-value")

    assert(tasks.any? { |t| t["id"] == dated.id.to_s })
    assert_nil tasks.find { |t| t["id"] == undated.id.to_s }
  end
```

Add to `test/controllers/projects_controller_test.rb`, right after the test `"index's stage-filtered Gantt still applies the placeholder when the type doesn't require dates"` (around line 569-577):

```ruby
  test "index's stage-filtered Gantt omits a project whose filtered stage has no dates, when the type has auto duration enabled" do
    field = FieldDefinition.create!(project_type: project_types(:instalaciones), key: "cantidad", label: "Cantidad", data_type: "number", position: 10)
    project_types(:instalaciones).update!(auto_stage_duration_enabled: true, duration_reference_field_definition: field)
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: { cantidad: "10" })
    slug = project_types(:instalaciones).slug

    get project_type_projects_path(slug), params: { stage_name: "Instalación", status: "" }
    assert_response :success
    tasks = json_data_attribute('[data-controller="gantt-project-list"]', "data-gantt-project-list-tasks-value")
    assert_nil tasks.find { |t| t["id"] == project.id.to_s }
  end
```

Add to `test/controllers/projects_controller_test.rb`, right after the test `"index's unfiltered Gantt omits a project whose stages are all undated, when the type requires dates"` (around line 693-702):

```ruby
  test "index's unfiltered Gantt omits a project whose stages are all undated, when the type has auto duration enabled" do
    field = FieldDefinition.create!(project_type: project_types(:instalaciones), key: "cantidad", label: "Cantidad", data_type: "number", position: 10)
    project_types(:instalaciones).update!(auto_stage_duration_enabled: true, duration_reference_field_definition: field)
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: { cantidad: "10" })
    slug = project_types(:instalaciones).slug

    get project_type_projects_path(slug)
    assert_response :success
    tasks = json_data_attribute('[data-controller="gantt-project-list"]', "data-gantt-project-list-tasks-value")
    assert_nil tasks.find { |t| t["id"] == project.id.to_s }
  end
```

- [ ] **Step 2: Run to confirm they fail**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n "/auto duration enabled/"`
Expected: all 3 new tests FAIL — the placeholder still gets applied today because only `require_stage_dates?` is checked, so `assert_nil` fails (a task is found for the undated stage/project).

- [ ] **Step 3: Update `show.html.erb`**

In `app/views/projects/show.html.erb`, replace line 34:

```erb
  require_dates = @project.project_type.require_stage_dates? || @project.project_type.auto_stage_duration_enabled?
```

- [ ] **Step 4: Update `_project_type_section.html.erb`**

In `app/views/projects/_project_type_section.html.erb`, replace line 92:

```erb
        next if (project_type.require_stage_dates? || project_type.auto_stage_duration_enabled?) && stage.dates_missing?
```

And replace line 97:

```erb
        next if (project_type.require_stage_dates? || project_type.auto_stage_duration_enabled?) && project.project_stages.all?(&:dates_missing?)
```

- [ ] **Step 5: Run the new tests to confirm they pass**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n "/auto duration enabled/"`
Expected: all 3 PASS

- [ ] **Step 6: Run the full controller test file**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: all PASS, 0 failures — in particular every pre-existing `require_stage_dates` Gantt-omission test (lines 305-327, 558-587, 693-711) must still pass unmodified, since `instalaciones` defaults to both flags `false` in those tests unless a test explicitly turns one on.

- [ ] **Step 7: Run the full test suite**

Run: `bin/rails test`
Expected: all PASS, 0 failures.

- [ ] **Step 8: Commit**

```bash
git add app/views/projects/show.html.erb app/views/projects/_project_type_section.html.erb test/controllers/projects_controller_test.rb
git commit -m "Omitir del Gantt las etapas pendientes también para tipos con duración automática"
```
