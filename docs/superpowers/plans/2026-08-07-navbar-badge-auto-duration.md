# Navbar Badge Auto Duration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `ApplicationHelper#pending_stage_dates_count` counts projects of `auto_stage_duration_enabled` types too, not just `require_stage_dates` ones — matching the "Pendientes de fecha" panel and the Gantt omissions fixed earlier today.

**Architecture:** One `.where` clause in the helper's query changes from an ActiveRecord hash filter on a single column to a raw SQL `OR` between the two `project_types` boolean columns.

**Tech Stack:** Rails 7.2, Minitest (`ActionView::TestCase`).

## Global Constraints

- Zero behavior change for project types with both flags off, or with only `require_stage_dates` on — the existing "ignores project types that don't require dates" test must keep passing unmodified (its fixture, `instalaciones`, defaults both flags to `false`).
- Same "any stage missing `start_date` or `end_date`" criterion — only the `project_types` filter changes.
- Do not touch the panel or the Gantt views — this plan is scoped to `application_helper.rb` and its test file only.

---

### Task 1: Widen the navbar badge query to both flags

**Files:**
- Modify: `app/helpers/application_helper.rb:41`
- Test: `test/helpers/application_helper_test.rb`

**Interfaces:**
- Consumes: `ProjectType#require_stage_dates`, `ProjectType#auto_stage_duration_enabled` (existing boolean columns).
- Produces: no new interface — last task of this plan.

- [ ] **Step 1: Write the failing test**

Add to `test/helpers/application_helper_test.rb`, right after the test `"pending_stage_dates_count counts visible projects with an undated stage, only for types that require dates"` (line 39-46):

```ruby
  test "pending_stage_dates_count counts visible projects with an undated stage, for types with auto duration enabled too" do
    field = FieldDefinition.create!(project_type: project_types(:instalaciones), key: "cantidad", label: "Cantidad", data_type: "number", position: 10)
    project_types(:instalaciones).update!(auto_stage_duration_enabled: true, duration_reference_field_definition: field)
    pending = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: { cantidad: "10" })
    complete = Project.create!(project_type: project_types(:instalaciones), name: "Torre Sur", custom_fields: { cantidad: "10" })
    complete.project_stages.each { |stage| stage.update!(start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 1, 10)) }

    assert_equal 1, pending_stage_dates_count(users(:juan))
  end
```

- [ ] **Step 2: Run to confirm it fails**

Run: `bin/rails test test/helpers/application_helper_test.rb -n test_pending_stage_dates_count_counts_visible_projects_with_an_undated_stage_for_types_with_auto_duration_enabled_too`
Expected: FAIL — `assert_equal 1, ...` gets `0`, since the current query only matches `require_stage_dates: true`.

- [ ] **Step 3: Widen the query**

In `app/helpers/application_helper.rb`, replace line 41:

```ruby
      .where("project_types.require_stage_dates = TRUE OR project_types.auto_stage_duration_enabled = TRUE")
```

(This replaces `.where(project_types: { require_stage_dates: true })` — same position in the chain, everything else in the method is unchanged.)

- [ ] **Step 4: Run the test to confirm it passes**

Run: `bin/rails test test/helpers/application_helper_test.rb -n test_pending_stage_dates_count_counts_visible_projects_with_an_undated_stage_for_types_with_auto_duration_enabled_too`
Expected: PASS

- [ ] **Step 5: Run the full helper test file**

Run: `bin/rails test test/helpers/application_helper_test.rb`
Expected: all PASS, 0 failures — in particular the two pre-existing `pending_stage_dates_count` tests (lines 39-52) must still pass unmodified, since `instalaciones` defaults both flags to `false` and the second test never turns either on.

- [ ] **Step 6: Run the full test suite**

Run: `bin/rails test`
Expected: all PASS, 0 failures.

- [ ] **Step 7: Commit**

```bash
git add app/helpers/application_helper.rb test/helpers/application_helper_test.rb
git commit -m "Contar también los tipos con duración automática en el badge de pendientes de la navbar"
```
