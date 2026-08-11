# Eliminar N+1 en el detalle de proyecto Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cut `ProjectsController#show`'s query count from the 53-97 seen in production logs down to a small constant, by eliminating a real N+1 on PaperTrail version history and scoping an unbounded "load every project" query.

**Architecture:** Two independent, single-file fixes on the same page. Task 1 adds `.includes(:item)` to the controller's version query. Task 2 scopes the view's project-association-picker query to only the project types actually linkable from this project, reusing data already computed in the same block. Neither task depends on the other's code — they touch different files (controller vs. view) and can be implemented in parallel.

**Tech Stack:** Rails 7.2, PaperTrail 17.0.0 (`belongs_to :item, polymorphic: true`), Minitest (`ActionDispatch::IntegrationTest`, the `count_sql_queries` helper already defined at the bottom of `test/controllers/projects_controller_test.rb` — reuse it, do not redefine it).

## Global Constraints

- Do not use `assert_queries_count { block }` without an explicit expected count to compare two call results — it returns the block's return value, not a query count, and silently no-ops. Use the existing `count_sql_queries` helper instead.
- Do not touch the `can_create_associated_project?` loop in `show.html.erb` (a separate, smaller, out-of-scope N+1 documented in the spec) or anything about Heroku/infrastructure.
- No pagination or limit changes — `@project_change_versions` already has `.limit(50)`; only fix how those (already-limited) records load their associations.

---

### Task 1: `.includes(:item)` on `@project_change_versions`

**Files:**
- Modify: `app/controllers/projects_controller.rb:37-46`
- Test: `test/controllers/projects_controller_test.rb`

**Interfaces:**
- Produces: nothing consumed by Task 2 — fully independent.

- [ ] **Step 1: Write the failing tests**

Add to `test/controllers/projects_controller_test.rb` (near the other `show`-related tests):

```ruby
  test "show doesn't add a query per PaperTrail history version (item N+1)" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    stage = project.project_stages.first

    get project_path(project) # warm up one-time class-loading queries before measuring

    2.times { |i| stage.update!(progress_percent: i + 10) }
    queries_for_two_versions = count_sql_queries { get project_path(project) }

    3.times { |i| stage.update!(progress_percent: i + 30) }
    queries_for_five_versions = count_sql_queries { get project_path(project) }

    assert_equal queries_for_two_versions, queries_for_five_versions,
      "more PaperTrail history must not add more queries (no N+1 on version.item)"
  end

  test "show's Historial still displays the stage name for a ProjectStage version" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    stage = project.project_stages.first
    stage.update!(progress_percent: 50)

    get project_path(project)
    assert_response :success
    assert_select "body", /Etapa: #{Regexp.escape(stage.name)}/
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n "/PaperTrail history version|Historial still displays/"`
Expected: the query-count test FAILS (five-version count higher than two-version count — one extra query per extra `ProjectStage`-type version). The display test likely already passes (this is a regression-proofing test, not a new-feature test) — that's fine, it exists to prove Step 3 doesn't break the existing display.

- [ ] **Step 3: Add the eager-load**

In `app/controllers/projects_controller.rb`, change:

```ruby
  def show
    @project_change_versions = PaperTrail::Version
      .where(item_type: "Project", item_id: @project.id)
      .or(PaperTrail::Version.where(item_type: "ProjectStage", item_id: @project.project_stage_ids))
      .order(created_at: :desc)
      .limit(50)

    whodunnit_ids = @project_change_versions.map(&:whodunnit).compact
    @version_authors = User.where(id: whodunnit_ids).index_by { |u| u.id.to_s }
  end
```

to:

```ruby
  def show
    @project_change_versions = PaperTrail::Version
      .where(item_type: "Project", item_id: @project.id)
      .or(PaperTrail::Version.where(item_type: "ProjectStage", item_id: @project.project_stage_ids))
      .order(created_at: :desc)
      .limit(50)
      .includes(:item)

    whodunnit_ids = @project_change_versions.map(&:whodunnit).compact
    @version_authors = User.where(id: whodunnit_ids).index_by { |u| u.id.to_s }
  end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n "/PaperTrail history version|Historial still displays/"`
Expected: PASS (2/2) — the query-count test proves the two measurements are now equal regardless of history size.

- [ ] **Step 5: Run the full suite**

Run: `bin/rails test`
Expected: 0 failures, 0 errors.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/projects_controller.rb test/controllers/projects_controller_test.rb
git commit -m "Precargar item en el historial de cambios del proyecto (elimina N+1)"
```

---

### Task 2: Scope `projects_by_other_type` to linkable project types

**Files:**
- Modify: `app/views/projects/show.html.erb:139-145`
- Test: `test/controllers/projects_controller_test.rb`

**Interfaces:**
- Produces: nothing consumed by Task 1 — fully independent.

- [ ] **Step 1: Write the failing test**

Add to `test/controllers/projects_controller_test.rb`:

```ruby
  test "the associations form's dependent-select options exclude project types with no linking association" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    linked_type = ProjectType.create!(name: "Mantenimiento", slug: "mantenimiento")
    ProjectTypeAssociation.create!(from_project_type: project_types(:instalaciones), to_project_type: linked_type, label: "Mantenimiento")
    Project.create!(project_type: linked_type, name: "Proyecto vinculable", custom_fields: {})

    unrelated_type = ProjectType.create!(name: "Sin relación", slug: "sin-relacion")
    Project.create!(project_type: unrelated_type, name: "Proyecto no vinculable", custom_fields: {})

    get project_path(project)
    assert_response :success

    options = json_data_attribute('[data-controller="dependent-select"]', "data-dependent-select-options-value")
    project_names = options.values.flatten(1).map { |_id, name| name }

    assert_includes project_names, "Proyecto vinculable"
    assert_not_includes project_names, "Proyecto no vinculable"
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n "/dependent-select options exclude/"`
Expected: FAIL — "Proyecto no vinculable" is currently included (the query loads every project regardless of type).

- [ ] **Step 3: Scope the query**

In `app/views/projects/show.html.erb`, change:

```erb
<%
  applicable_associations = ProjectTypeAssociation.where(from_project_type: @project.project_type).or(ProjectTypeAssociation.where(to_project_type: @project.project_type))
  association_options = applicable_associations.map do |a|
    other_type_id = a.from_project_type_id == @project.project_type_id ? a.to_project_type_id : a.from_project_type_id
    [a.label, a.id, { data: { key: other_type_id } }]
  end
  projects_by_other_type = Project.where.not(id: @project.id).order(:name).group_by(&:project_type_id)
    .transform_values { |projects| projects.map { |p| [p.id, p.name] } }
%>
```

to:

```erb
<%
  applicable_associations = ProjectTypeAssociation.where(from_project_type: @project.project_type).or(ProjectTypeAssociation.where(to_project_type: @project.project_type))
  association_options = applicable_associations.map do |a|
    other_type_id = a.from_project_type_id == @project.project_type_id ? a.to_project_type_id : a.from_project_type_id
    [a.label, a.id, { data: { key: other_type_id } }]
  end
  relevant_type_ids = association_options.map { |_, _, opts| opts[:data][:key] }.uniq
  projects_by_other_type = Project.where.not(id: @project.id).where(project_type_id: relevant_type_ids).order(:name).group_by(&:project_type_id)
    .transform_values { |projects| projects.map { |p| [p.id, p.name] } }
%>
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n "/dependent-select options exclude/"`
Expected: PASS

- [ ] **Step 5: Run the full suite**

Run: `bin/rails test`
Expected: 0 failures, 0 errors — confirms the existing "index shows one Gantt task per project" and other association-form tests (e.g. `new prefills a shared field...`) still pass unchanged.

- [ ] **Step 6: Commit**

```bash
git add app/views/projects/show.html.erb test/controllers/projects_controller_test.rb
git commit -m "Acotar el selector de proyectos para asociar a los tipos realmente vinculables"
```

---

### Task 3: Full suite verification

**Files:** none (verification only)

- [ ] **Step 1: Run the full test suite**

Run: `bin/rails test`
Expected: 0 failures, 0 errors — confirms Tasks 1 and 2 together don't conflict (they touch different files, but both modify behavior on the same `show` page).

- [ ] **Step 2: Manual smoke check**

Visit `/projects/:id` for a project with some change history and at least one configured `ProjectTypeAssociation`, signed in as an existing user:
- Confirm "Historial de cambios" still shows stage names correctly for stage-level changes.
- Confirm the "Vincular" project dropdown in Asociaciones only offers projects of types actually linkable to this one.

- [ ] **Step 3: Commit any fixups**

If Step 1 or 2 surfaced issues, commit fixes individually with a message describing what broke and why.
