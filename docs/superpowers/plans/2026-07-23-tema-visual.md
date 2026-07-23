# Tema visual propio, badges de estado en español — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the app a graphite/professional color identity instead of default Bootstrap blue, and translate `Project#status` ("active"/"archived") to Spanish badges wherever it's shown.

**Architecture:** Pure CSS-variable overrides on top of the existing Bootstrap 5.3 CDN link (no new dependency, no HTML restructuring) plus one small helper method reused by both the status column and the filter dropdown.

**Tech Stack:** Ruby on Rails, Minitest, Bootstrap 5.3.3 (CDN, unchanged).

## Global Constraints

- No new gems, no external font/CSS CDN beyond the Bootstrap link already present.
- No changes to page structure/HTML layout — only CSS variables and the status-label/badge swap.
- `--bs-primary` and `--bs-primary-rgb` must be updated together — Bootstrap derives hover/focus states and `-subtle` variants from the RGB pair; leaving them out of sync breaks those derived styles even though this app doesn't use `-subtle` classes yet.

---

### Task 1: Custom theme + Spanish status badges

**Files:**
- Modify: `app/assets/stylesheets/application.css` (append the theme variables)
- Modify: `app/helpers/application_helper.rb` (add `status_label`/`status_badge`)
- Create: `test/helpers/application_helper_test.rb`
- Modify: `app/views/projects/index.html.erb` (status column + filter dropdown)
- Modify: `test/controllers/projects_controller_test.rb` (assert Spanish badge text + filter option text)

**Interfaces:**
- Consumes: `Project#status` (`db/schema.rb`, unchanged — string column, values `"active"`/`"archived"` today).
- Produces: `ApplicationHelper#status_label(status)` → String, `ApplicationHelper#status_badge(status)` → `ActiveSupport::SafeBuffer` (an HTML `<span>`). No later task in this plan depends on these — this is the only task.

- [ ] **Step 1: Write the failing helper tests**

Create `test/helpers/application_helper_test.rb`:

```ruby
require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "status_label translates known statuses to Spanish" do
    assert_equal "Activo", status_label("active")
    assert_equal "Archivado", status_label("archived")
  end

  test "status_label returns the raw value for an unknown status" do
    assert_equal "weird_status", status_label("weird_status")
  end

  test "status_badge renders a colored badge with the Spanish label" do
    assert_match(/badge bg-success/, status_badge("active"))
    assert_match(/Activo/, status_badge("active"))
    assert_match(/badge bg-secondary/, status_badge("archived"))
    assert_match(/Archivado/, status_badge("archived"))
  end

  test "status_badge falls back to a neutral badge for an unknown status" do
    assert_match(/badge bg-light text-dark/, status_badge("weird_status"))
    assert_match(/weird_status/, status_badge("weird_status"))
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/helpers/application_helper_test.rb`
Expected: FAIL — `NoMethodError: undefined method 'status_label'` (the helper methods don't exist yet).

- [ ] **Step 3: Implement the helper methods**

Replace `app/helpers/application_helper.rb` in full:

```ruby
module ApplicationHelper
  STATUS_LABELS = { "active" => "Activo", "archived" => "Archivado" }.freeze
  STATUS_BADGE_CLASSES = { "active" => "bg-success", "archived" => "bg-secondary" }.freeze

  def status_label(status)
    STATUS_LABELS.fetch(status, status)
  end

  def status_badge(status)
    tag.span(status_label(status), class: "badge #{STATUS_BADGE_CLASSES.fetch(status, 'bg-light text-dark')}")
  end
end
```

- [ ] **Step 4: Run the helper tests to verify they pass**

Run: `bin/rails test test/helpers/application_helper_test.rb`
Expected: PASS (4 tests)

- [ ] **Step 5: Write the failing controller tests**

Add to `test/controllers/projects_controller_test.rb`, inside the existing test class:

```ruby
  test "index shows the project status as a Spanish badge, not the raw value" do
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get projects_path
    assert_response :success
    assert_select "span.badge.bg-success", "Activo"
    assert_select "body", text: /\bactive\b/, count: 0
  end

  test "index shows Spanish labels in the status filter while keeping English values" do
    Project.create!(
      project_type: project_types(:instalaciones), name: "Torre Vieja", custom_fields: {}, status: "archived"
    )
    get projects_path
    assert_response :success
    assert_select "select#status option[value=?]", "archived", text: "Archivado"
  end
```

- [ ] **Step 6: Run the tests to verify they fail**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: FAIL — the status column still renders the raw string (`active`), and the filter `<option>` still shows the raw value as its text.

- [ ] **Step 7: Update the status column and the filter dropdown**

Edit `app/views/projects/index.html.erb` — two changes:

1. The filter `<select>` (currently on the line `<%= form.select :status, @statuses, ...`):

```erb
  <div class="col-auto">
    <%= form.label :status, "Estado", class: "form-label" %>
    <%= form.select :status, @statuses.map { |s| [status_label(s), s] },
          { include_blank: "Todos", selected: params[:status] }, class: "form-select" %>
  </div>
```

2. The table cell (currently `<td><%= project.status %></td>`):

```erb
          <td><%= status_badge(project.status) %></td>
```

- [ ] **Step 8: Run the tests to verify they pass**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: PASS (all tests)

- [ ] **Step 9: Add the theme CSS**

Append to `app/assets/stylesheets/application.css` (the file currently ends with the generator's comment block — add this after it, don't remove the comment):

```css
:root {
  --bs-primary: #2c3e50;
  --bs-primary-rgb: 44, 62, 80;
  --bs-link-color: #2c3e50;
  --bs-link-hover-color: #1a252f;
  --bs-border-radius: 0.5rem;
  --bs-border-radius-sm: 0.35rem;
  --bs-border-radius-lg: 0.65rem;
}

.btn-primary {
  --bs-btn-bg: var(--bs-primary);
  --bs-btn-border-color: var(--bs-primary);
  --bs-btn-hover-bg: #1a252f;
  --bs-btn-hover-border-color: #1a252f;
}

.navbar-brand {
  font-weight: 600;
  letter-spacing: 0.01em;
}
```

- [ ] **Step 10: Run the full suite**

Run: `bin/rails test`
Expected: PASS — CSS changes don't affect Minitest (no test covers rendered styles), but this confirms Steps 1-8 didn't break anything else.

- [ ] **Step 11: Manual verification**

Run: `bin/rails server`, visit `/` (sign in first if needed), confirm:
- Buttons and links show the graphite color instead of Bootstrap's default blue.
- The status column shows green "Activo"/gray "Archivado" badges instead of raw text.
- The "Estado" filter dropdown shows "Activo"/"Archivado" as option text (view page source or inspect element to confirm the underlying `value` attributes are still `active`/`archived`).
- Filtering by "Archivado" in the dropdown still works (submits and narrows the list) — this exercises that the `value` attribute wasn't accidentally changed to the Spanish label.

- [ ] **Step 12: Commit**

```bash
git add app/assets/stylesheets/application.css app/helpers/application_helper.rb \
  test/helpers/application_helper_test.rb app/views/projects/index.html.erb \
  test/controllers/projects_controller_test.rb
git commit -m "Add a custom graphite theme and Spanish status badges"
```

---

## Final verification

- [ ] Run `bin/rails test` once more — expect a clean pass.
- [ ] `grep -rn '"active"\|"archived"' app/views/` should show no raw status text left in any view — only the helper's internal `STATUS_LABELS`/`STATUS_BADGE_CLASSES` maps in `app/helpers/application_helper.rb` should contain those literal strings now.
