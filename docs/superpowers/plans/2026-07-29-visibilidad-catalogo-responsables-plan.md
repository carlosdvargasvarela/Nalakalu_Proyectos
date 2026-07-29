# Visibilidad del catálogo de Responsables Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the `Responsible` catalog (`/admin/responsibles`) discoverable via the navbar, and visible (read-only, with a link to the full admin) from a project type's edit view.

**Architecture:** Two small view changes — a navbar link, and a new read-only card in `admin/project_types/show.html.erb`. No controller/model/DB changes.

**Tech Stack:** Rails 7.2, Minitest with fixtures.

## Global Constraints

- No DB/model changes, no new dependency.
- The "Responsables" card in `project_types#show` is read-only (name + color badge, link to `/admin/responsibles`) — no edit/delete buttons there, full CRUD stays exclusively at `/admin/responsibles`.

---

### Task 1: Navbar link + read-only card on project type show

**Files:**
- Modify: `app/views/layouts/_navbar.html.erb`
- Modify: `app/views/admin/project_types/show.html.erb`
- Test: `test/controllers/navbar_test.rb`
- Test: `test/controllers/admin/project_types_controller_test.rb`

**Interfaces:**
- None — pure view changes, no new methods/routes (both routes already exist: `admin_responsibles_path` from a previous feature).

- [ ] **Step 1: Write the failing tests**

Add to `test/controllers/navbar_test.rb`, inside `class NavbarTest`:

```ruby
  test "navbar includes a link to Responsables for admin" do
    sign_in users(:juan)
    get root_path
    follow_redirect!
    assert_response :success
    assert_select "nav a[href=?]", admin_responsibles_path
  end

  test "navbar does not show the Responsables link to a gerente" do
    sign_in users(:carla)
    get root_path
    follow_redirect!
    assert_response :success
    assert_select "nav a[href=?]", admin_responsibles_path, count: 0
  end
```

Add to `test/controllers/admin/project_types_controller_test.rb`, inside `class Admin::ProjectTypesControllerTest`:

```ruby
  test "show lists the Responsible catalog with a link to manage it" do
    Responsible.create!(name: "Ana Gómez", color: "#ff0000")
    get admin_project_type_path(project_types(:instalaciones))
    assert_response :success
    assert_select ".card-header", "Responsables"
    assert_select "body", /Ana Gómez/
    assert_select "a[href=?]", admin_responsibles_path, text: "Administrar responsables"
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/controllers/navbar_test.rb test/controllers/admin/project_types_controller_test.rb -n "/Responsables|Responsible catalog/"`
Expected: FAIL — no such link/card exists yet.

- [ ] **Step 3: Add the navbar link**

In `app/views/layouts/_navbar.html.erb`, add right after `link_to "Administración", admin_project_types_path, class: "nav-link"` and before `link_to "Usuarios", admin_users_path, class: "nav-link"` (or immediately after "Usuarios" — either position is fine, keep it inside the same `if user_signed_in? && current_user.admin?` block):

```erb
        <%= link_to "Responsables", admin_responsibles_path, class: "nav-link" %>
```

- [ ] **Step 4: Add the read-only card to `admin/project_types/show.html.erb`**

Add this card right after the existing "Tipos de responsable" card:

```erb
<div class="card mb-4">
  <div class="card-header">Responsables</div>
  <div class="card-body">
    <%= link_to "Administrar responsables", admin_responsibles_path, class: "btn btn-outline-secondary btn-sm mb-2" %>
    <ul class="list-group list-group-flush">
      <% Responsible.order(:name).each do |responsible| %>
        <li class="list-group-item">
          <span class="badge me-2" style="background-color: <%= responsible.color %>">&nbsp;</span><%= responsible.name %>
        </li>
      <% end %>
    </ul>
  </div>
</div>
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bin/rails test test/controllers/navbar_test.rb test/controllers/admin/project_types_controller_test.rb`
Expected: PASS

- [ ] **Step 6: Run the full suite**

Run: `bin/rails test`
Expected: PASS, no regressions.

- [ ] **Step 7: Commit**

```bash
git add app/views/layouts/_navbar.html.erb app/views/admin/project_types/show.html.erb \
  test/controllers/navbar_test.rb test/controllers/admin/project_types_controller_test.rb
git commit -m "Add navbar link and read-only card for the Responsible catalog"
```
