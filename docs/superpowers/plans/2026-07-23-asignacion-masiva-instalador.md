# Filtro "Sin instalador" + Asignación masiva de instalador — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On the `projects#index` screen, let the user filter for projects that have no installer assigned, and bulk-assign one installer to many selected projects at once.

**Architecture:** Two additive changes to `ProjectsController`/`projects/index.html.erb` plus one new controller action and route. No new models, no schema changes — installer assignment is still just writing to `Project#custom_fields` at the key whose `FieldDefinition.reference_table == "installers"`, exactly like the existing single-project edit form and `filter_by_installer` already do.

**Tech Stack:** Rails 7.2.3 controller/view code, Minitest integration tests, vanilla JS (no Turbo/Stimulus/jQuery in this app), Bootstrap 5.3.3 classes already in use.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-23-asignacion-masiva-instalador-design.md`.
- No new gems, no new JS libraries — vanilla `fetch`/DOM APIs only, matching every other interactive bit of UI in this app (see `admin/project_types/show.html.erb`'s drag-reorder script).
- Installer-reference field resolution must go through `FieldDefinition.reference_table == "installers"` per project's own `project_type` — never hardcode a field key like `"instalador"` (same principle as `Project#installer` and `filter_by_installer`).
- Bulk assignment lives only on `projects#index` (the "Proyectos" home screen) — out of scope for `projects#tracker` (Seguimiento).
- The bulk-assign `<form>` and each row's `_archive_button` `<form>` must not be nested (HTML forbids nested `<form>` elements) — checkboxes use the HTML5 `form="bulk-assign-form"` attribute to associate with a form declared before the table, not wrapping it.
- Route for the new action goes before `resources :projects` in `config/routes.rb` (same reasoning as `projects/seguimiento` — a literal path segment must precede the resourceful route or `resources :projects` captures it as `/projects/:id`).

---

## File Structure

- Modify `app/controllers/projects_controller.rb` — add `filter_by_no_installer` private method, `installer_id == "none"` branch in `index`, and the new `bulk_assign_installer` public action.
- Modify `config/routes.rb` — add one `patch` route.
- Modify `app/views/projects/index.html.erb` — add "Sin instalador" option to the Instalador `<select>`, add the bulk-assign form + checkboxes + select-all script above/around the "Listado" table.
- Modify `test/controllers/projects_controller_test.rb` — add tests for all of the above (existing file, single controller test suite for this controller, following its established pattern).

---

### Task 1: "Sin instalador" filter

**Files:**
- Modify: `app/controllers/projects_controller.rb:4-12` (the `index` action) and add a new private method near `filter_by_installer` (currently at line 83).
- Modify: `app/views/projects/index.html.erb:28-32` (the Instalador `<select>`).
- Test: `test/controllers/projects_controller_test.rb`.

**Interfaces:**
- Consumes: `FieldDefinition.where(reference_table: "installers")` (existing scope, same as `filter_by_installer`), `Project#custom_fields` (jsonb).
- Produces: `ProjectsController#filter_by_no_installer(scope)` — takes an `ActiveRecord::Relation` of `Project`, returns a relation filtered to projects where every installer-reference custom field is null/blank. Used only within `index`; no other task depends on it.

- [ ] **Step 1: Write the failing test**

Add to `test/controllers/projects_controller_test.rb` (place it near the other `"index filters by installer"` test):

```ruby
  test "index filters by Sin instalador" do
    sin_instalador = Project.create!(
      project_type: project_types(:instalaciones), name: "Sin Instalador", custom_fields: {}
    )
    con_instalador = Project.create!(
      project_type: project_types(:instalaciones), name: "Con Instalador",
      custom_fields: { instalador: installers(:juan_perez).id }
    )

    get projects_path, params: { installer_id: "none" }
    assert_response :success
    assert_match(/#{sin_instalador.name}/, response.body)
    assert_no_match(/#{con_instalador.name}/, response.body)
  end

  test "index shows a Sin instalador option in the Instalador filter" do
    get projects_path
    assert_response :success
    assert_select "select#installer_id option[value=?]", "none", text: "Sin instalador"
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n "/Sin instalador/"`
Expected: FAIL — first test shows both projects (no `"none"` handling yet), second test can't find the option.

- [ ] **Step 3: Implement the filter in the controller**

In `app/controllers/projects_controller.rb`, replace this line in `index`:

```ruby
    @projects = filter_by_installer(@projects, params[:installer_id]) if params[:installer_id].present?
```

with:

```ruby
    if params[:installer_id] == "none"
      @projects = filter_by_no_installer(@projects)
    elsif params[:installer_id].present?
      @projects = filter_by_installer(@projects, params[:installer_id])
    end
```

Add this private method directly after `filter_by_installer` (which ends at line 87, just before the closing `end` of the class):

```ruby
  def filter_by_no_installer(scope)
    keys = FieldDefinition.where(reference_table: "installers").distinct.pluck(:key)
    return scope if keys.empty?
    keys.reduce(scope) { |s, key| s.where("custom_fields ->> ? IS NULL OR custom_fields ->> ? = ''", key, key) }
  end
```

- [ ] **Step 4: Update the Instalador select in the view**

In `app/views/projects/index.html.erb`, replace:

```erb
      <div class="col-auto">
        <%= form.label :installer_id, "Instalador", class: "form-label" %>
        <%= form.select :installer_id, @installers.collect { |i| [i.name, i.id] },
              { include_blank: "Todos", selected: params[:installer_id] }, class: "form-select" %>
      </div>
```

with:

```erb
      <div class="col-auto">
        <%= form.label :installer_id, "Instalador", class: "form-label" %>
        <%= form.select :installer_id,
              [["Sin instalador", "none"]] + @installers.collect { |i| [i.name, i.id] },
              { include_blank: "Todos", selected: params[:installer_id] }, class: "form-select" %>
      </div>
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: all PASS (full file, to also confirm no regression in the other installer-filter tests).

- [ ] **Step 6: Commit**

```bash
git add app/controllers/projects_controller.rb app/views/projects/index.html.erb test/controllers/projects_controller_test.rb
git commit -m "Add Sin instalador filter option to projects#index"
```

---

### Task 2: `bulk_assign_installer` action and route

**Files:**
- Modify: `config/routes.rb:19` (add the new route right before `resources :projects`).
- Modify: `app/controllers/projects_controller.rb` (add the public action).
- Test: `test/controllers/projects_controller_test.rb`.

**Interfaces:**
- Consumes: none from Task 1 (independent controller action); reuses the same `FieldDefinition.where(reference_table: "installers")` pattern.
- Produces: `PATCH /projects/bulk_assign_installer` (route helper `bulk_assign_installer_projects_path`), accepting params `installer_id` and `project_ids` (array). Task 3's view form posts to this path.

- [ ] **Step 1: Write the failing tests**

Add to `test/controllers/projects_controller_test.rb`:

```ruby
  test "bulk_assign_installer assigns the installer to every selected project" do
    otro_instalador = Installer.create!(name: "Otro Instalador")
    proyecto_a = Project.create!(project_type: project_types(:instalaciones), name: "Proyecto A", custom_fields: {})
    proyecto_b = Project.create!(project_type: project_types(:instalaciones), name: "Proyecto B", custom_fields: {})

    patch bulk_assign_installer_projects_path, params: {
      installer_id: otro_instalador.id, project_ids: [proyecto_a.id, proyecto_b.id]
    }

    assert_redirected_to projects_path
    assert_equal otro_instalador.id.to_s, proyecto_a.reload.custom_fields["instalador"]
    assert_equal otro_instalador.id.to_s, proyecto_b.reload.custom_fields["instalador"]
    follow_redirect!
    assert_match(/Instalador asignado a 2 proyecto\(s\)/, response.body)
  end

  test "bulk_assign_installer preserves existing query params on redirect" do
    installer = installers(:juan_perez)
    project = Project.create!(project_type: project_types(:instalaciones), name: "Proyecto A", custom_fields: {})

    patch bulk_assign_installer_projects_path, params: {
      installer_id: installer.id, project_ids: [project.id], project_type_id: project_types(:instalaciones).id
    }

    assert_redirected_to projects_path(project_type_id: project_types(:instalaciones).id)
  end

  test "bulk_assign_installer without an installer chosen does nothing and redirects with an alert" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Proyecto A", custom_fields: {})

    patch bulk_assign_installer_projects_path, params: { installer_id: "", project_ids: [project.id] }

    assert_redirected_to projects_path
    assert_nil project.reload.custom_fields["instalador"]
    follow_redirect!
    assert_match(/Elegí un instalador y al menos un proyecto/, response.body)
  end

  test "bulk_assign_installer without any project selected does nothing and redirects with an alert" do
    installer = installers(:juan_perez)

    patch bulk_assign_installer_projects_path, params: { installer_id: installer.id, project_ids: [] }

    assert_redirected_to projects_path
    follow_redirect!
    assert_match(/Elegí un instalador y al menos un proyecto/, response.body)
  end

  test "bulk_assign_installer skips a project whose type has no installer-reference field" do
    other_type = ProjectType.create!(name: "Mantenimiento", slug: "mantenimiento")
    installer = installers(:juan_perez)
    con_campo = Project.create!(project_type: project_types(:instalaciones), name: "Con Campo", custom_fields: {})
    sin_campo = Project.create!(project_type: other_type, name: "Sin Campo", custom_fields: {})

    patch bulk_assign_installer_projects_path, params: {
      installer_id: installer.id, project_ids: [con_campo.id, sin_campo.id]
    }

    assert_equal installer.id.to_s, con_campo.reload.custom_fields["instalador"]
    assert_equal({}, sin_campo.reload.custom_fields)
    follow_redirect!
    assert_match(/Instalador asignado a 1 proyecto\(s\)/, response.body)
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n "/bulk_assign_installer/"`
Expected: FAIL — `bulk_assign_installer_projects_path` is undefined (no route yet).

- [ ] **Step 3: Add the route**

In `config/routes.rb`, replace:

```ruby
  get "projects/seguimiento", to: "projects#tracker", as: :tracker_projects
  resources :projects
```

with:

```ruby
  get "projects/seguimiento", to: "projects#tracker", as: :tracker_projects
  patch "projects/bulk_assign_installer", to: "projects#bulk_assign_installer", as: :bulk_assign_installer_projects
  resources :projects
```

- [ ] **Step 4: Implement the controller action**

In `app/controllers/projects_controller.rb`, add this public method after `update` (before the `private` line):

```ruby
  def bulk_assign_installer
    if params[:installer_id].blank? || Array(params[:project_ids]).empty?
      redirect_to projects_path(request.query_parameters), alert: "Elegí un instalador y al menos un proyecto." and return
    end

    count = 0
    Project.where(id: params[:project_ids]).find_each do |project|
      key = project.project_type.field_definitions.find_by(reference_table: "installers")&.key
      next unless key

      project.custom_fields = project.custom_fields.merge(key => params[:installer_id])
      count += 1 if project.save
    end

    redirect_to projects_path(request.query_parameters), notice: "Instalador asignado a #{count} proyecto(s)."
  end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add config/routes.rb app/controllers/projects_controller.rb test/controllers/projects_controller_test.rb
git commit -m "Add bulk_assign_installer action and route"
```

---

### Task 3: Bulk-assign UI on `projects#index`

**Files:**
- Modify: `app/views/projects/index.html.erb:132-158` (the "Listado" card).
- Test: `test/controllers/projects_controller_test.rb`.

**Interfaces:**
- Consumes: `bulk_assign_installer_projects_path` (from Task 2), `@installers` (already assigned in `index`), `_archive_button` partial (existing, unchanged).
- Produces: nothing consumed by later tasks — this is the last task in the plan.

- [ ] **Step 1: Write the failing tests**

Add to `test/controllers/projects_controller_test.rb`:

```ruby
  test "index renders a bulk-assign form with a checkbox per project, not nested inside another form" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get projects_path
    assert_response :success

    assert_select "form#bulk-assign-form[action=?]", bulk_assign_installer_projects_path
    assert_select "form#bulk-assign-form select[name=?]", "installer_id"
    assert_select "form#bulk-assign-form input[type=submit][value=?]", "Asignar"
    assert_select "input[type=checkbox][name=?][form=bulk-assign-form]", "project_ids[]", value: project.id.to_s

    doc = Nokogiri::HTML5(response.body)
    bulk_form = doc.at_css("#bulk-assign-form")
    assert_nil bulk_form.at_css("form"), "the archive button's form must not be nested inside the bulk-assign form"
  end

  test "index's select-all checkbox toggles every project checkbox via JS" do
    get projects_path
    assert_response :success
    assert_select "input#select-all-projects[type=checkbox]"
    assert_match(/select-all-projects/, response.body)
    assert_match(/project_ids\[\]/, response.body)
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n "/bulk-assign/"`
Expected: FAIL — no `#bulk-assign-form` in the rendered page yet.

- [ ] **Step 3: Implement the view**

In `app/views/projects/index.html.erb`, replace the entire "Listado" card block:

```erb
  <div class="card mb-4">
    <div class="card-header">Listado</div>
    <div class="card-body p-0">
      <table class="table table-striped mb-0">
        <thead>
          <tr><th>Nombre</th><th>Tipo</th><th>Estado</th><th>Avance</th><th></th></tr>
        </thead>
        <tbody>
          <% projects_list.each do |project| %>
            <tr>
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
      </table>
    </div>
  </div>
```

with:

```erb
  <%= form_with url: bulk_assign_installer_projects_path, method: :patch, local: true,
        id: "bulk-assign-form", class: "d-flex gap-2 align-items-end mb-3" do |f| %>
    <div>
      <%= f.label :installer_id, "Asignar instalador a los seleccionados", class: "form-label" %>
      <%= f.select :installer_id, @installers.collect { |i| [i.name, i.id] },
            { include_blank: "Elegí un instalador" }, class: "form-select" %>
    </div>
    <%= f.submit "Asignar", class: "btn btn-primary" %>
  <% end %>

  <div class="card mb-4">
    <div class="card-header">Listado</div>
    <div class="card-body p-0">
      <table class="table table-striped mb-0">
        <thead>
          <tr>
            <th><input type="checkbox" id="select-all-projects"></th>
            <th>Nombre</th><th>Tipo</th><th>Estado</th><th>Avance</th><th></th>
          </tr>
        </thead>
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
      </table>
    </div>
  </div>

  <script>
    document.getElementById("select-all-projects").addEventListener("change", function (e) {
      document.querySelectorAll('input[name="project_ids[]"]').forEach(function (cb) { cb.checked = e.target.checked; });
    });
  </script>
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add app/views/projects/index.html.erb test/controllers/projects_controller_test.rb
git commit -m "Add bulk-assign checkboxes and installer select to projects#index"
```

---

## Final Verification

- [ ] Run the full test suite: `bin/rails test`
- [ ] Expected: all tests pass, no regressions in `projects_controller_test.rb` or elsewhere.
