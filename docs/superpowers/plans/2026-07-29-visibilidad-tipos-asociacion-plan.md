# Visibilidad de tipos de asociación Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `/admin/project_type_associations` (built in the previous feature) has no navbar link — same oversight already fixed once for `/admin/responsibles`. Add the missing link.

**Architecture:** One view change, no model/DB/logic involved.

**Tech Stack:** Rails 7.2, Minitest with fixtures.

## Global Constraints

- No DB/model changes, no new dependency.

---

### Task 1: Navbar link for tipos de asociación

**Files:**
- Modify: `app/views/layouts/_navbar.html.erb`
- Test: `test/controllers/navbar_test.rb`

**Interfaces:**
- None — pure view change, the route (`admin_project_type_associations_path`) already exists.

- [ ] **Step 1: Write the failing tests**

Add to `test/controllers/navbar_test.rb`, inside `class NavbarTest`:

```ruby
  test "navbar includes a link to Tipos de asociación for admin" do
    sign_in users(:juan)
    get root_path
    follow_redirect!
    assert_response :success
    assert_select "nav a[href=?]", admin_project_type_associations_path
  end

  test "navbar does not show the Tipos de asociación link to a gerente" do
    sign_in users(:carla)
    get root_path
    follow_redirect!
    assert_response :success
    assert_select "nav a[href=?]", admin_project_type_associations_path, count: 0
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/controllers/navbar_test.rb -n "/Tipos de asociación/"`
Expected: FAIL — no such link exists yet.

- [ ] **Step 3: Add the navbar link**

In `app/views/layouts/_navbar.html.erb`, add right after `link_to "Responsables", admin_responsibles_path, class: "nav-link"` and before `link_to "Usuarios", admin_users_path, class: "nav-link"` (same admin-only `if` block):

```erb
        <%= link_to "Tipos de asociación", admin_project_type_associations_path, class: "nav-link" %>
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/controllers/navbar_test.rb`
Expected: PASS

- [ ] **Step 5: Run the full suite**

Run: `bin/rails test`
Expected: PASS, no regressions.

- [ ] **Step 6: Commit**

```bash
git add app/views/layouts/_navbar.html.erb test/controllers/navbar_test.rb
git commit -m "Add navbar link for project type associations"
```
