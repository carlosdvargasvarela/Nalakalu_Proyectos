# Columna de responsables en la tabla "Listado" Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show each project's assigned (project-wide) responsibles in the "Listado" table on `/projects/tipo/:slug`, highlighting the one matching the active "Tipo de responsable" filter — without introducing an N+1.

**Architecture:** One eager-load addition in `ProjectsController#build_section`, one new `<td>` in the existing table loop in `_project_type_section.html.erb` reusing `ProjectResponsible`'s own denormalized `responsible_name`/`responsible_color` columns (no new association traversal), plus a one-line cleanup of a now-redundant `.includes` call the new eager-load makes counterproductive.

**Tech Stack:** Rails 7.2, Minitest (`ActionDispatch::IntegrationTest`, `assert_queries_count` from `ActiveRecord::Assertions::QueryAssertions`, auto-included via `rails/test_help`).

## Global Constraints

- Only **project-wide** responsibles (`project_stage_id.nil?` / `ProjectResponsible#project_wide?`) — never per-stage assignments.
- Use `pr.responsible_name` / `pr.responsible_color` (denormalized snapshot columns already on `project_responsibles`, set by `ProjectResponsible#snapshot_responsible`) — never `pr.responsible.name`/`.color`, to avoid an extra association hop.
- The responsible whose `responsible_type_id` matches the page's active `responsible_type_id` filter (the same `selected_type` local already computed in the template) sorts first and gets a `fw-bold` class. No filter active → no highlighting, no reordering beyond DB order.
- No responsibles assigned → empty cell, no placeholder text.
- Visual style: a small colored circle (`rounded-circle`, same inline-style pattern as `app/views/projects/_gantt_legend.html.erb`) + `<small>Tipo: Nombre</small>` — no new CSS, no new component.

---

### Task 1: Eager-load fix, redundant-includes cleanup, and the new column

**Files:**
- Modify: `app/controllers/projects_controller.rb:289`
- Modify: `app/views/projects/_project_type_section.html.erb:117,243,254` (header + new cell, and the redundant-includes cleanup at line 117)
- Test: `test/controllers/projects_controller_test.rb`

**Interfaces:**
- Consumes: `selected_type` (a `ResponsibleType` or `nil`, template-local, already assigned at `_project_type_section.html.erb:122` from `section_params[:responsible_type_id]` — this plan does not introduce it, only reads it further down in the same template).
- Produces: nothing new consumed by other tasks — this is the only task in the plan.

- [ ] **Step 1: Write the failing tests**

Add to `test/controllers/projects_controller_test.rb` (anywhere among the other `index`/table-rendering tests, e.g. near "index's Gantt legend appears only when a responsible type is selected"):

```ruby
  test "index's Listado table shows each project's project-wide responsibles" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    ProjectResponsible.create!(project: project, responsible: responsibles(:ana_gomez), responsible_type: responsible_types(:instalador))

    get project_type_projects_path(project_types(:instalaciones).slug)
    assert_response :success
    assert_select "td", text: /Instalador Fixture: Ana Gómez/
  end

  test "index's Listado table omits a responsible assigned to a specific stage, not the whole project" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    stage = project.project_stages.first # instalaciones' stage_templates fixtures auto-create these on save
    ProjectResponsible.create!(project: project, responsible: responsibles(:ana_gomez), responsible_type: responsible_types(:instalador), project_stage: stage)

    get project_type_projects_path(project_types(:instalaciones).slug)
    assert_response :success
    assert_select "td", text: /Ana Gómez/, count: 0
  end

  test "index's Listado table bolds the responsible matching the active type filter, not others" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    disenador = Responsible.create!(name: "Diana Diseñadora")
    ResponsibleProjectType.create!(responsible: disenador, project_type: project_types(:instalaciones), responsible_type: responsible_types(:disenador))
    ProjectResponsible.create!(project: project, responsible: responsibles(:ana_gomez), responsible_type: responsible_types(:instalador))
    ProjectResponsible.create!(project: project, responsible: disenador, responsible_type: responsible_types(:disenador))

    get project_type_projects_path(project_types(:instalaciones).slug, responsible_type_id: responsible_types(:instalador).id)
    assert_response :success

    doc = Nokogiri::HTML5(response.body)
    bold_cell = doc.css("td .fw-bold").text
    assert_match(/Ana Gómez/, bold_cell)
    assert_no_match(/Diana Diseñadora/, bold_cell)
  end

  test "index's Listado table renders an empty cell for a project with no responsibles" do
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_type_projects_path(project_types(:instalaciones).slug)
    assert_response :success # no error rendering the new column with zero responsibles
  end

  test "index's Listado table doesn't add an extra query per project for responsibles" do
    3.times do |i|
      project = Project.create!(project_type: project_types(:instalaciones), name: "Torre #{i}", custom_fields: {})
      ProjectResponsible.create!(project: project, responsible: responsibles(:ana_gomez), responsible_type: responsible_types(:instalador))
    end

    # Warm up any one-time class-loading queries before measuring.
    get project_type_projects_path(project_types(:instalaciones).slug)

    queries_for_three = assert_queries_count { get project_type_projects_path(project_types(:instalaciones).slug) }

    2.times do |i|
      project = Project.create!(project_type: project_types(:instalaciones), name: "Otra #{i}", custom_fields: {})
      ProjectResponsible.create!(project: project, responsible: responsibles(:ana_gomez), responsible_type: responsible_types(:instalador))
    end

    queries_for_five = assert_queries_count { get project_type_projects_path(project_types(:instalaciones).slug) }

    assert_equal queries_for_three, queries_for_five, "adding more projects/responsibles must not add more queries (no N+1)"
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n "/Listado table/"`
Expected: FAIL — no "Responsables" column exists yet, so the badge-presence and bold-highlight assertions find nothing; the query-count test likely still "passes" at this point (nothing to compare against a regression yet) but re-run it after Step 4 to confirm it actually catches a regression, per Step 6.

- [ ] **Step 3: Fix the controller eager-load**

In `app/controllers/projects_controller.rb:289`, change:

```ruby
    projects = Project.visible_to(current_user).where(project_type: project_type).includes(:project_type, project_stages: :stage_template).order(:name)
```

to:

```ruby
    projects = Project.visible_to(current_user).where(project_type: project_type).includes(:project_type, project_stages: :stage_template, project_responsibles: :responsible_type).order(:name)
```

- [ ] **Step 4: Remove the now-redundant `.includes` in the Gantt tasks block**

In `app/views/projects/_project_type_section.html.erb:117`, change:

```erb
        responsibles: project.project_responsibles.includes(:responsible_type).map { |pr| { type: pr.responsible_type.name, name: pr.responsible_name, color: pr.responsible_color } },
```

to:

```erb
        responsibles: project.project_responsibles.map { |pr| { type: pr.responsible_type.name, name: pr.responsible_name, color: pr.responsible_color } },
```

(Calling `.includes` again on an association Step 3 already eager-loaded returns a brand-new relation and re-queries instead of reusing the preload — dropping it here is what makes the eager-load in Step 3 actually pay off instead of adding a query back.)

- [ ] **Step 5: Add the column**

In `app/views/projects/_project_type_section.html.erb:243`, change:

```erb
              <th>Nombre</th><th>Estado</th><th>Avance</th><th></th>
```

to:

```erb
              <th>Nombre</th><th>Estado</th><th>Responsables</th><th>Avance</th><th></th>
```

Then, right after the "Estado" `<td>` (currently `<td><%= status_badge(project.status) %></td>`, around line 254), insert:

```erb
                <td>
                  <% project.project_responsibles.select(&:project_wide?).sort_by { |pr| pr.responsible_type_id == selected_type&.id ? 0 : 1 }.each do |pr| %>
                    <div class="d-flex align-items-center gap-1<%= " fw-bold" if pr.responsible_type_id == selected_type&.id %>">
                      <span class="rounded-circle d-inline-block" style="width: 0.65rem; height: 0.65rem; background-color: <%= pr.responsible_color %>;"></span>
                      <small><%= pr.responsible_type.name %>: <%= pr.responsible_name %></small>
                    </div>
                  <% end %>
                </td>
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n "/Listado table/"`
Expected: PASS (5/5), including the query-count test — confirm its two `assert_queries_count` calls return the SAME number (proving 3 vs. 5 projects/responsibles doesn't add queries).

- [ ] **Step 7: Run the full suite**

Run: `bin/rails test`
Expected: 0 failures, 0 errors — confirms the controller eager-load change and the `.includes` removal in the Gantt block don't regress any Gantt-task-building test (`gantt_tasks[:responsibles]` still needs to produce the same shape of data, just sourced from the preload instead of its own query).

- [ ] **Step 8: Commit**

```bash
git add app/controllers/projects_controller.rb app/views/projects/_project_type_section.html.erb test/controllers/projects_controller_test.rb
git commit -m "Agregar columna de responsables a la tabla Listado, con eager-load para evitar N+1"
```

---

### Task 2: Full suite verification

**Files:** none (verification only)

- [ ] **Step 1: Run the full test suite**

Run: `bin/rails test`
Expected: 0 failures, 0 errors.

- [ ] **Step 2: Manual smoke check**

Visit `/projects/tipo/<slug>` for a project type with at least one project that has both a project-wide responsible and (optionally) a stage-specific one, signed in as an existing user:
- Confirm the "Responsables" column appears between "Estado" and "Avance".
- Confirm a stage-specific assignment does NOT show in the column.
- Apply the "Tipo de responsable" filter at the top and confirm the matching responsible in the table turns bold and sorts first, while other types on the same project stay unbold below it.
- Clear the filter and confirm nothing is bold, but all project-wide responsibles still show.

- [ ] **Step 3: Commit any fixups**

If Step 1 or 2 surfaced issues, commit fixes individually with a message describing what broke and why.
