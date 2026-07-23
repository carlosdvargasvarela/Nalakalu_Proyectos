# Paginación, Gantt con scroll y filtro de rango de fechas — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `projects#index` scale past ~10-20 projects: paginate the "Listado" table, cap the Gantt's height with automatic scroll, and let the user narrow the visible date range with a Desde/Hasta filter.

**Architecture:** Three additive, mostly-independent changes to `ProjectsController#index` and `projects/index.html.erb`. No schema changes, no new gems — pagination is a Ruby array slice over the already-loaded filtered project list (the Gantt and KPI cards need the full filtered set regardless), the Gantt scroll is pure CSS, and the date-range filter is a SQL join against `project_stages`' existing `start_date`/`end_date` columns.

**Tech Stack:** Rails 7.2.3 controller/view code, Minitest integration tests, Bootstrap 5.3.3 `.pagination` component (already loaded via CDN), plain HTML5 `<input type="date">`.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-23-paginacion-gantt-scroll-rango-fechas-design.md`.
- No new gems (no Kaminari/Pagy) — pagination is a plain Ruby `Array#drop`/`Array#first` slice over the array already loaded for the Gantt/KPIs.
- The Gantt and the KPI cards (Total/Vencidos/Finalizados) must always reflect the FULL filtered set, never just the current page of the table.
- The date-range filter must query `project_stages.start_date`/`project_stages.end_date` (real DB columns) — never `Project#start_date`/`#end_date` (Ruby-computed methods, not usable in SQL `where`).
- With neither `from_date` nor `to_date` given, behavior must be unchanged from today (show everything the other filters allow).
- This plan only touches `projects#index` — `projects#tracker` (Seguimiento) is out of scope.

---

## File Structure

- Modify `app/controllers/projects_controller.rb` — add `@page` assignment in `index`, add `filter_by_date_range` private method and its call in `index`.
- Modify `app/views/projects/index.html.erb` — add `max-height`/`overflow-y` style to `#gantt`, add Desde/Hasta fields to the filter form, add pagination slicing + nav controls around the "Listado" table.
- Modify `test/controllers/projects_controller_test.rb` — add tests for all three changes (existing file, same controller test suite used by every prior round on this screen).

---

### Task 1: Gantt max-height with automatic scroll

**Files:**
- Modify: `app/views/projects/index.html.erb` (the `<div id="gantt">` line, currently `<div id="gantt" class="mb-0"></div>`).
- Test: `test/controllers/projects_controller_test.rb`.

**Interfaces:** None — this is a self-contained CSS change with no controller/model involvement, and no other task depends on it.

- [ ] **Step 1: Write the failing test**

Add to `test/controllers/projects_controller_test.rb` (near the other Gantt-related tests):

```ruby
  test "index renders the Gantt container with a fixed max-height and vertical scroll" do
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get projects_path
    assert_response :success
    assert_select "#gantt[style=?]", "max-height: 630px; overflow-y: auto;"
  end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n "/fixed max-height/"`
Expected: FAIL — no `style` attribute on `#gantt` yet.

- [ ] **Step 3: Add the style**

In `app/views/projects/index.html.erb`, replace:

```erb
      <div id="gantt" class="mb-0"></div>
```

with:

```erb
      <div id="gantt" class="mb-0" style="max-height: 630px; overflow-y: auto;"></div>
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: all PASS (full file, to confirm no regression).

- [ ] **Step 5: Commit**

```bash
git add app/views/projects/index.html.erb test/controllers/projects_controller_test.rb
git commit -m "Cap the general Gantt's height with automatic vertical scroll"
```

---

### Task 2: "Desde/Hasta" date-range filter

**Files:**
- Modify: `app/controllers/projects_controller.rb:4-12` (the `index` action) and add a new private method near `filter_by_no_installer`.
- Modify: `app/views/projects/index.html.erb:17-37` (the filters form).
- Test: `test/controllers/projects_controller_test.rb`.

**Interfaces:**
- Consumes: `ProjectStage` (existing model, `belongs_to :project`, real `start_date`/`end_date` date columns per `db/schema.rb:38-51`).
- Produces: `ProjectsController#filter_by_date_range(scope, from_date, to_date)` — private method, takes an `ActiveRecord::Relation` of `Project` plus two date-string params (may be blank), returns a relation. Used only within `index`; Task 3 (pagination) slices whatever this produces, so it must not change `@projects`' shape (still a `Project` relation).

- [ ] **Step 1: Write the failing tests**

Add to `test/controllers/projects_controller_test.rb`:

```ruby
  test "index filters by a Desde/Hasta date range that overlaps a project's stages" do
    dentro = Project.create!(project_type: project_types(:instalaciones), name: "Dentro del Rango", custom_fields: {})
    dentro.project_stages.order(:id).first.update!(start_date: Date.new(2026, 3, 1), end_date: Date.new(2026, 3, 10))

    fuera = Project.create!(project_type: project_types(:instalaciones), name: "Fuera del Rango", custom_fields: {})
    fuera.project_stages.each { |s| s.update!(start_date: Date.new(2026, 6, 1), end_date: Date.new(2026, 6, 10)) }

    get projects_path, params: { from_date: "2026-02-01", to_date: "2026-04-01" }
    assert_response :success
    assert_match(/#{dentro.name}/, response.body)
    assert_no_match(/#{fuera.name}/, response.body)
  end

  test "index without from_date or to_date shows all projects allowed by the other filters" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get projects_path
    assert_response :success
    assert_match(/#{project.name}/, response.body)
  end

  test "index shows Desde and Hasta date fields in the filter form" do
    get projects_path
    assert_response :success
    assert_select "input[type=date][name=?]", "from_date"
    assert_select "input[type=date][name=?]", "to_date"
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n "/Desde|Hasta|from_date/"`
Expected: FAIL — `from_date`/`to_date` params are ignored, and the fields don't exist in the form yet.

- [ ] **Step 3: Implement the controller filter**

In `app/controllers/projects_controller.rb`, add this line to `index`, right after the existing installer-filter conditional:

```ruby
    @projects = filter_by_date_range(@projects, params[:from_date], params[:to_date])
```

So `index` reads:

```ruby
  def index
    @project_types = ProjectType.all
    @statuses = Project.distinct.pluck(:status).compact
    @installers = Installer.all
    @projects = Project.includes(:project_type, project_stages: :stage_template)
    @projects = params[:status].present? ? @projects.where(status: params[:status]) : @projects.where.not(status: "archived")
    @projects = @projects.where(project_type_id: params[:project_type_id]) if params[:project_type_id].present?
    if params[:installer_id] == "none"
      @projects = filter_by_no_installer(@projects)
    elsif params[:installer_id].present?
      @projects = filter_by_installer(@projects, params[:installer_id])
    end
    @projects = filter_by_date_range(@projects, params[:from_date], params[:to_date])
  end
```

Add this private method directly after `filter_by_no_installer`:

```ruby
  def filter_by_date_range(scope, from_date, to_date)
    return scope if from_date.blank? && to_date.blank?
    scope = scope.joins(:project_stages).distinct
    scope = scope.where("project_stages.end_date >= ?", from_date) if from_date.present?
    scope = scope.where("project_stages.start_date <= ?", to_date) if to_date.present?
    scope
  end
```

- [ ] **Step 4: Add the Desde/Hasta fields to the view**

In `app/views/projects/index.html.erb`, replace:

```erb
      <div class="col-auto align-self-end">
        <%= form.submit "Filtrar", class: "btn btn-primary" %>
      </div>
```

with:

```erb
      <div class="col-auto">
        <%= form.label :from_date, "Desde", class: "form-label" %>
        <%= form.date_field :from_date, value: params[:from_date], class: "form-control" %>
      </div>
      <div class="col-auto">
        <%= form.label :to_date, "Hasta", class: "form-label" %>
        <%= form.date_field :to_date, value: params[:to_date], class: "form-control" %>
      </div>
      <div class="col-auto align-self-end">
        <%= form.submit "Filtrar", class: "btn btn-primary" %>
      </div>
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/projects_controller.rb app/views/projects/index.html.erb test/controllers/projects_controller_test.rb
git commit -m "Add Desde/Hasta date-range filter to projects#index"
```

---

### Task 3: Pagination of the "Listado" table

**Files:**
- Modify: `app/controllers/projects_controller.rb:4-15` (the `index` action).
- Modify: `app/views/projects/index.html.erb:44-46, 154-170` (the `projects_list` assignment and the table's `<tbody>`).
- Test: `test/controllers/projects_controller_test.rb`.

**Interfaces:**
- Consumes: `@projects` (an `ActiveRecord::Relation` of `Project`, already filtered by every prior filter including Task 2's `filter_by_date_range`).
- Produces: `@page` (an `Integer >= 1`, set in the controller). The view computes `per_page`, `total_pages`, and `page_projects` locally from `projects_list` and `@page` — nothing here is consumed by a later task (this is the last task in the plan).

- [ ] **Step 1: Write the failing tests**

Add to `test/controllers/projects_controller_test.rb`:

```ruby
  test "index paginates the Listado table at 20 projects per page" do
    25.times { |n| Project.create!(project_type: project_types(:instalaciones), name: "Proyecto #{n}", custom_fields: {}) }

    get projects_path
    assert_response :success
    assert_select "table tbody tr", count: 20

    get projects_path, params: { page: 2 }
    assert_response :success
    assert_select "table tbody tr", count: 5
  end

  test "index's KPI cards and Gantt tasks count all filtered projects, not just the current page" do
    25.times { |n| Project.create!(project_type: project_types(:instalaciones), name: "Proyecto #{n}", custom_fields: {}) }

    get projects_path
    assert_response :success
    assert_select ".card .display-6", "25"
    assert_select "script#gantt-tasks" do |elements|
      tasks = JSON.parse(elements.first.text)
      assert_equal 25, tasks.size
    end
  end

  test "index shows no pagination controls when there are 20 projects or fewer" do
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get projects_path
    assert_response :success
    assert_select "ul.pagination", count: 0
  end

  test "index shows pagination controls that preserve the current filter" do
    other_type = ProjectType.create!(name: "Mantenimiento", slug: "mantenimiento")
    25.times { |n| Project.create!(project_type: project_types(:instalaciones), name: "Proyecto #{n}", custom_fields: {}) }
    Project.create!(project_type: other_type, name: "Otro Tipo", custom_fields: {})

    get projects_path, params: { project_type_id: project_types(:instalaciones).id }
    assert_response :success
    assert_select "ul.pagination"
    assert_select "a.page-link[href=?]", projects_path(project_type_id: project_types(:instalaciones).id, page: 2)
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n "/paginat/"`
Expected: FAIL — the table currently renders all 25 rows with no pagination controls.

- [ ] **Step 3: Set `@page` in the controller**

In `app/controllers/projects_controller.rb`, add this line to `index`, right after the `filter_by_date_range` call added in Task 2:

```ruby
    @page = [params[:page].to_i, 1].max
```

So `index` ends:

```ruby
    @projects = filter_by_date_range(@projects, params[:from_date], params[:to_date])
    @page = [params[:page].to_i, 1].max
  end
```

- [ ] **Step 4: Slice the projects list and update the table**

In `app/views/projects/index.html.erb`, replace:

```erb
  <%
    projects_list = @projects.to_a
  %>
```

with:

```erb
  <%
    projects_list = @projects.to_a
    per_page = 20
    total_pages = (projects_list.size / per_page.to_f).ceil
    page_projects = projects_list.drop((@page - 1) * per_page).first(per_page)
  %>
```

Then replace the `<tbody>` block:

```erb
        <tbody>
          <% projects_list.each do |project| %>
            <tr>
              <td><%= check_box_tag "project_ids[]", project.id, false, id: nil, form: "bulk-assign-form" %></td>
              <td><%= link_to project.name, project_path(project) %></td>
              <td><%= project.project_type.name %></td>
              <td><%= status_badge(project.status) %></td>
              <td>
                <%= progress_status_badge(project.progress_status) %>
                <%= overdue_badge if project.overdue? %>
              </td>
              <td>
                <%= link_to "Editar", edit_project_path(project), class: "btn btn-outline-secondary btn-sm" %>
                <%= render "archive_button", project: project %>
              </td>
            </tr>
          <% end %>
        </tbody>
```

with:

```erb
        <tbody>
          <% page_projects.each do |project| %>
            <tr>
              <td><%= check_box_tag "project_ids[]", project.id, false, id: nil, form: "bulk-assign-form" %></td>
              <td><%= link_to project.name, project_path(project) %></td>
              <td><%= project.project_type.name %></td>
              <td><%= status_badge(project.status) %></td>
              <td>
                <%= progress_status_badge(project.progress_status) %>
                <%= overdue_badge if project.overdue? %>
              </td>
              <td>
                <%= link_to "Editar", edit_project_path(project), class: "btn btn-outline-secondary btn-sm" %>
                <%= render "archive_button", project: project %>
              </td>
            </tr>
          <% end %>
        </tbody>
```

Then add pagination controls right after the closing `</table>` but still inside the "Listado" card's `.card-body`. Replace:

```erb
      </table>
    </div>
  </div>
```

with:

```erb
      </table>
      <% if total_pages > 1 %>
        <nav class="p-3">
          <ul class="pagination mb-0">
            <li class="page-item <%= "disabled" if @page <= 1 %>">
              <%= link_to "Anterior", projects_path(request.query_parameters.merge(page: @page - 1)), class: "page-link" %>
            </li>
            <% (1..total_pages).each do |n| %>
              <li class="page-item <%= "active" if n == @page %>">
                <%= link_to n, projects_path(request.query_parameters.merge(page: n)), class: "page-link" %>
              </li>
            <% end %>
            <li class="page-item <%= "disabled" if @page >= total_pages %>">
              <%= link_to "Siguiente", projects_path(request.query_parameters.merge(page: @page + 1)), class: "page-link" %>
            </li>
          </ul>
        </nav>
      <% end %>
    </div>
  </div>
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/projects_controller.rb app/views/projects/index.html.erb test/controllers/projects_controller_test.rb
git commit -m "Paginate the Listado table at 20 projects per page"
```

---

## Final Verification

- [ ] Run the full test suite: `bin/rails test`
- [ ] Expected: all tests pass, no regressions anywhere else in the app.
