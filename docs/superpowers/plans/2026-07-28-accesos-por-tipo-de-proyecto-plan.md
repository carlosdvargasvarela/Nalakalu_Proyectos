# Accesos por tipo de proyecto + UI de accesos escalable Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let an admin grant a gerente edit access to an entire `ProjectType` (present and future projects of that type), and split the `/admin/users/:id` access UI into a small per-type table plus a searchable flat table of individual projects.

**Architecture:** New `ProjectTypeAccess` join model (`user`, `project_type`, `can_edit`) coexists with the existing `ProjectAccess`. `User#can_edit_project?` is `true` if either source grants it — resolved dynamically on every check, no snapshot. `Admin::UsersController` syncs both tables from one form, behind the existing `sync_project_access` marker. The view splits the current grouped-by-type table into two: a type-grants table and a flat, JS-filterable project table.

**Tech Stack:** Rails 7.2, Minitest fixtures, vanilla JS (no new dependency), Bootstrap tables (existing `admin_card` helper).

## Global Constraints

- `ProjectTypeAccess` has no "view" column — gerente already sees all projects by role (unchanged); visor access stays exclusively per-project via `ProjectAccess` (spec: "Alcance", bullet 3).
- `can_view_project?` does not change.
- One `form_with` / one `user-access-form` — do not add a second form for the type-grants table (spec: "Admin::UsersController" section).
- No new JS library for the project search — vanilla JS `input` listener filtering rows by `data-name` (spec: "Alcance", bullet 4; "Fuera de alcance").
- `ProjectsController#create` / `ImportsController#create` are NOT touched — they keep creating a redundant-but-harmless per-project `ProjectAccess` row (spec: "Fuera de alcance").
- A type-level grant always wins over a conflicting per-project `can_edit: false` row — no "revoke within a granted type" mechanism (spec: "Edge cases").

---

### Task 1: `ProjectTypeAccess` model + migration + `User#can_edit_project?`

**Files:**
- Create: `db/migrate/<timestamp>_create_project_type_accesses.rb`
- Create: `app/models/project_type_access.rb`
- Modify: `app/models/user.rb`
- Test: `test/models/project_type_access_test.rb`
- Test: `test/models/user_test.rb`

**Interfaces:**
- Produces: `ProjectTypeAccess` (belongs_to `:user`, `:project_type`; `can_edit:boolean`), `User#project_type_accesses` association, `User#can_edit_project?(project)` unchanged signature/return (boolean), now also checking type-level grants.

- [ ] **Step 1: Write the failing model tests**

```ruby
# test/models/project_type_access_test.rb
require "test_helper"

class ProjectTypeAccessTest < ActiveSupport::TestCase
  test "valid with user and project_type" do
    access = ProjectTypeAccess.new(user: users(:carla), project_type: project_types(:instalaciones))
    assert access.valid?
  end

  test "invalid with a duplicate user/project_type pair" do
    ProjectTypeAccess.create!(user: users(:carla), project_type: project_types(:instalaciones), can_edit: true)
    dup = ProjectTypeAccess.new(user: users(:carla), project_type: project_types(:instalaciones))
    assert_not dup.valid?
  end

  test "can_edit defaults to false" do
    access = ProjectTypeAccess.create!(user: users(:carla), project_type: project_types(:instalaciones))
    assert_equal false, access.can_edit
  end
end
```

Add to `test/models/user_test.rb`, inside `class UserTest`:

```ruby
  test "gerente with a ProjectTypeAccess can edit any project of that type, including new ones" do
    gerente = users(:carla)
    ProjectTypeAccess.create!(user: gerente, project_type: project_types(:instalaciones), can_edit: true)

    existing = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    assert gerente.can_edit_project?(existing)

    later = Project.create!(project_type: project_types(:instalaciones), name: "Torre Sur", custom_fields: {})
    assert gerente.can_edit_project?(later)
  end

  test "gerente without a ProjectTypeAccess or ProjectAccess cannot edit" do
    gerente = users(:carla)
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    assert_not gerente.can_edit_project?(project)
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/models/project_type_access_test.rb test/models/user_test.rb`
Expected: FAIL — `NameError: uninitialized constant ProjectTypeAccess`

- [ ] **Step 3: Generate and edit the migration**

Run: `bin/rails generate migration CreateProjectTypeAccesses` and replace its contents with:

```ruby
class CreateProjectTypeAccesses < ActiveRecord::Migration[7.2]
  def change
    create_table :project_type_accesses do |t|
      t.references :user, null: false, foreign_key: true
      t.references :project_type, null: false, foreign_key: true
      t.boolean :can_edit, null: false, default: false

      t.timestamps

      t.index [:user_id, :project_type_id], unique: true
    end
  end
end
```

Run: `bin/rails db:migrate`

- [ ] **Step 4: Create the model**

```ruby
# app/models/project_type_access.rb
class ProjectTypeAccess < ApplicationRecord
  belongs_to :user
  belongs_to :project_type

  validates :user_id, uniqueness: { scope: :project_type_id }
end
```

- [ ] **Step 5: Update `User`**

In `app/models/user.rb`, add the association next to `has_many :project_accesses, dependent: :destroy`:

```ruby
  has_many :project_type_accesses, dependent: :destroy
```

Replace `can_edit_project?`:

```ruby
  def can_edit_project?(project)
    return true if admin?
    return false if visor?
    project_accesses.exists?(project_id: project.id, can_edit: true) ||
      project_type_accesses.exists?(project_type_id: project.project_type_id, can_edit: true)
  end
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bin/rails test test/models/project_type_access_test.rb test/models/user_test.rb`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add db/migrate db/schema.rb app/models/project_type_access.rb app/models/user.rb test/models/project_type_access_test.rb test/models/user_test.rb
git commit -m "Add ProjectTypeAccess model for type-level edit grants"
```

---

### Task 2: `Admin::UsersController` — sync type grants alongside project grants

**Files:**
- Modify: `app/controllers/admin/users_controller.rb`
- Test: `test/controllers/admin/users_controller_test.rb`

**Interfaces:**
- Consumes: `ProjectTypeAccess` (Task 1), `User#project_type_accesses`.
- Produces: `@project_types` ivar (available to the view in Task 3), `sync_access_grants!` (renamed from `sync_project_accesses!`) handling both `params[:project_access]` and `params[:project_type_access]`.

- [ ] **Step 1: Write the failing controller tests**

Add to `test/controllers/admin/users_controller_test.rb`, inside the class:

```ruby
  test "update assigns project type access from the checkboxes" do
    patch admin_user_path(users(:carla)), params: {
      user: { email: users(:carla).email, role: "gerente" },
      sync_project_access: "1",
      project_type_access: { project_types(:instalaciones).id.to_s => { "edit" => "1" } }
    }
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    assert users(:carla).reload.can_edit_project?(project)
  end

  test "update without the access-form marker does not touch existing project type access" do
    ProjectTypeAccess.create!(user: users(:carla), project_type: project_types(:instalaciones), can_edit: true)

    patch admin_user_path(users(:carla)), params: { user: { email: users(:carla).email, role: "gerente" } }

    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    assert users(:carla).reload.can_edit_project?(project)
  end

  test "edit exposes project types for the type-grants table" do
    get edit_admin_user_path(users(:maria))
    assert_response :success
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/controllers/admin/users_controller_test.rb`
Expected: FAIL — the first new test fails because no `ProjectTypeAccess` row is created (params ignored); the others still pass since `@project_types` isn't referenced yet by any assertion. Confirm the first one fails before continuing.

- [ ] **Step 3: Update the controller**

In `app/controllers/admin/users_controller.rb`:

Replace both occurrences of `@projects = Project.all.includes(:project_type)` (in `edit` and in the `update` failure branch) — add a line right after each:

```ruby
  def edit
    @projects = Project.all.includes(:project_type)
    @project_types = ProjectType.all
  end

  def update
    attrs = user_params
    attrs = attrs.except(:password, :password_confirmation) if attrs[:password].blank?
    if @user.update(attrs)
      sync_access_grants!
      redirect_to admin_users_path
    else
      @projects = Project.all.includes(:project_type)
      @project_types = ProjectType.all
      render :edit, status: :unprocessable_entity
    end
  end
```

Replace `sync_project_accesses!` (and its call site above, already updated to `sync_access_grants!`) with:

```ruby
  # ponytail: replaces all of the user's accesses on every save — O(proyectos totales +
  # tipos totales), fine at this pilot's scale. If it grows large, upgrade to diffing
  # (only create/destroy what changed) instead of destroy_all + recreate.
  #
  # Only runs when the request actually came from the access-grants form (marked by
  # `sync_project_access`). The email/role/password form is separate and never submits
  # `project_access`/`project_type_access` at all — without this guard, saving that form
  # would see absent params and wipe every existing grant.
  def sync_access_grants!
    return unless params[:sync_project_access] == "1"

    submitted_projects = params.fetch(:project_access, {})
    @user.project_accesses.destroy_all
    submitted_projects.each do |project_id, flags|
      next unless flags["view"] == "1"
      @user.project_accesses.create!(project_id: project_id, can_edit: flags["edit"] == "1")
    end

    submitted_types = params.fetch(:project_type_access, {})
    @user.project_type_accesses.destroy_all
    submitted_types.each do |project_type_id, flags|
      next unless flags["edit"] == "1"
      @user.project_type_accesses.create!(project_type_id: project_type_id, can_edit: true)
    end
  end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/controllers/admin/users_controller_test.rb`
Expected: PASS

The view still references the old grouped-by-type markup and doesn't use `@project_types` yet — that's fine, `edit` and `update` tests only assert `:success`/redirects, not markup content. Task 3 updates the view.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/admin/users_controller.rb test/controllers/admin/users_controller_test.rb
git commit -m "Sync project-type access grants in Admin::UsersController"
```

---

### Task 3: View — type-grants table + searchable flat project table

**Files:**
- Modify: `app/views/admin/users/_form.html.erb`
- Test: `test/controllers/admin/users_controller_test.rb`

**Interfaces:**
- Consumes: `@project_types` (Task 2), `user.project_type_accesses`, `user.project_accesses` (existing), `project_type_access[...]`/`project_access[...]` params (Task 2).

- [ ] **Step 1: Write the failing test**

Add to `test/controllers/admin/users_controller_test.rb`, inside the class:

```ruby
  test "edit renders the project type grants table and the project search box" do
    get edit_admin_user_path(users(:maria))
    assert_select "table#project-access-table"
    assert_select "input#project-access-search"
    assert_select "table", text: /Editar/, count: 2 # type-grants table + project table both have an "Editar" column
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/admin/users_controller_test.rb -n "/renders the project type grants/"`
Expected: FAIL — no element matches `table#project-access-table` or `input#project-access-search` yet (current view groups projects by type with no `id` and no search box).

- [ ] **Step 3: Replace the "Accesos a proyectos" card markup**

In `app/views/admin/users/_form.html.erb`, replace the whole block from `<%= admin_card("Accesos a proyectos") do %>` through its matching `<% end %>` with:

```erb
<% if user.persisted? %>
  <%= admin_card("Accesos a proyectos") do %>
    <h3 class="h6">Tipos de proyecto</h3>
    <p class="text-muted small">Da acceso de edición a todos los proyectos de ese tipo, incluidos los que se creen después.</p>
    <table class="table table-sm">
      <thead><tr><th>Tipo de proyecto</th><th>Editar</th></tr></thead>
      <tbody>
        <% @project_types.each do |project_type| %>
          <% type_access = user.project_type_accesses.find { |a| a.project_type_id == project_type.id } %>
          <tr>
            <td><%= project_type.name %></td>
            <td><%= check_box_tag "project_type_access[#{project_type.id}][edit]", "1", type_access&.can_edit || false, form: "user-access-form" %></td>
          </tr>
        <% end %>
      </tbody>
    </table>

    <h3 class="h6 mt-4">Proyectos individuales</h3>
    <p class="text-muted small">
      "Ver" alcanza para un rol Visor. "Editar" da acceso puntual a un proyecto fuera de su
      tipo asignado (solo tiene efecto extra para un rol Gerente; Admin siempre tiene acceso total).
    </p>
    <%= text_field_tag :project_access_search, nil, class: "form-control mb-2", placeholder: "Buscar proyecto...", id: "project-access-search" %>
    <table class="table table-sm" id="project-access-table">
      <thead><tr><th>Proyecto</th><th>Tipo</th><th>Ver</th><th>Editar</th></tr></thead>
      <tbody>
        <% @projects.each do |project| %>
          <% access = user.project_accesses.find { |a| a.project_id == project.id } %>
          <tr data-name="<%= project.name.downcase %>">
            <td><%= project.name %></td>
            <td><%= project.project_type.name %></td>
            <td><%= check_box_tag "project_access[#{project.id}][view]", "1", access.present?, form: "user-access-form" %></td>
            <td><%= check_box_tag "project_access[#{project.id}][edit]", "1", access&.can_edit || false, form: "user-access-form" %></td>
          </tr>
        <% end %>
      </tbody>
    </table>
    <script>
      document.getElementById("project-access-search").addEventListener("input", function (e) {
        var term = e.target.value.toLowerCase();
        document.querySelectorAll("#project-access-table tbody tr").forEach(function (row) {
          row.style.display = row.dataset.name.includes(term) ? "" : "none";
        });
      });
    </script>

    <%= form_with url: admin_user_path(user), method: :patch, id: "user-access-form" do %>
      <%= hidden_field_tag "user[email]", user.email %>
      <%= hidden_field_tag "user[role]", user.role %>
      <%= hidden_field_tag "sync_project_access", "1" %>
      <%= submit_tag "Guardar accesos", class: "btn btn-primary" %>
    <% end %>
  <% end %>
<% end %>
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/controllers/admin/users_controller_test.rb`
Expected: PASS (all tests in the file, including the ones from Task 2)

- [ ] **Step 5: Manual check of the search filter**

The `input`-listener filter is plain JS with no server-side test (same criterion the spec calls out for this app's other vanilla scripts). Start the app (`bin/dev` or your usual boot command), sign in as `juan@example.com` / `password123`, open `/admin/users/<id>/edit` for a user with several projects, type a few characters into "Buscar proyecto..." and confirm only matching rows stay visible.

- [ ] **Step 6: Commit**

```bash
git add app/views/admin/users/_form.html.erb test/controllers/admin/users_controller_test.rb
git commit -m "Split admin user access UI into type grants and searchable project table"
```
