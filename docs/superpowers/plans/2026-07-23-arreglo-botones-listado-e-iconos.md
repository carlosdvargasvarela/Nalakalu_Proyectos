# Arreglo de alineación de botones + íconos — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the real bug making the "Archivar" button drop to its own line below "Editar" (a silently-ignored `style:` option on `form_with`), align both buttons horizontally, and add Bootstrap Icons to both.

**Architecture:** A single small task — one partial fix (`_archive_button.html.erb`), one layout change (Bootstrap Icons CDN link), and two view updates (`_project_type_section.html.erb`'s table row, `show.html.erb`'s header). All four files change together for one coherent visual fix; nothing here is independently shippable in a meaningful way, but the change is small enough to stay one task.

**Tech Stack:** Rails 7.2.3 view code, Bootstrap 5.3.3 (already loaded), Bootstrap Icons 1.11.3 (new CDN CSS-only addition), Minitest.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-23-arreglo-botones-listado-e-iconos-design.md`.
- Root cause fix, not a workaround: `form_with`'s `style:` option is silently ignored (not a recognized top-level option) — the fix passes the class via `html: { class: "d-inline" }`, which `form_with` does recognize.
- The "Archivar" button changes from `<input type="submit">` (via `f.submit`) to `<button type="submit">` (via `f.button` with a block) — required to nest the `<i>` icon inside; `f.submit` only accepts a plain string label.
- No new JS — Bootstrap Icons is a CSS-only CDN addition (a `<link>` tag, exactly like the existing Bootstrap CSS link).
- Icons: `bi-pencil` for Editar, `bi-archive` for Archivar.
- Two pre-existing tests assert `input[value="Archivar"]` and must be updated to match the new `<button>` markup: `test/controllers/projects_controller_test.rb:86` and `:395`.

---

## File Structure

- Modify `app/views/layouts/application.html.erb` — add the Bootstrap Icons CDN link.
- Modify `app/views/projects/_archive_button.html.erb` — fix the `style:` bug, switch to `f.button` with the icon.
- Modify `app/views/projects/_project_type_section.html.erb` — wrap Editar+Archivar in a flex container, add the pencil icon to Editar.
- Modify `app/views/projects/show.html.erb` — add the pencil icon to its existing Editar link.
- Modify `test/controllers/projects_controller_test.rb` — update the 2 tests asserting on the old `<input>` markup.

---

### Task 1: Fix button alignment bug, add icons

**Files:**
- Modify: `app/views/layouts/application.html.erb:16` (the `<head>`, next to the existing Bootstrap CSS link).
- Modify: `app/views/projects/_archive_button.html.erb` (entire file).
- Modify: `app/views/projects/_project_type_section.html.erb:184-187` (the actions `<td>`).
- Modify: `app/views/projects/show.html.erb:10` (the Editar link in the header).
- Test: `test/controllers/projects_controller_test.rb:80-88` and `:391-397`.

**Interfaces:** None — this is a self-contained view/markup fix with no controller or model involvement, and no other task in this plan depends on it (it's the only task).

- [ ] **Step 1: Write the failing tests**

Add to `test/controllers/projects_controller_test.rb` (near the other index/show tests):

```ruby
  test "index's Editar and Archivar buttons are wrapped in a flex container with icons" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get projects_path
    assert_response :success
    assert_select "td .d-flex.gap-2 a.btn i.bi-pencil"
    assert_select "td .d-flex.gap-2 form button i.bi-archive"
  end

  test "show's Editar button includes the pencil icon" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_path(project)
    assert_response :success
    assert_select "a.btn i.bi-pencil"
  end

  test "layout loads Bootstrap Icons" do
    get projects_path
    assert_response :success
    assert_match(/bootstrap-icons/, response.body)
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n "/flex container with icons|pencil icon|Bootstrap Icons/"`
Expected: FAIL — no `.bi-pencil`/`.bi-archive` classes exist yet, no `.d-flex.gap-2` wrapper in the table cell, no Bootstrap Icons link in the layout.

- [ ] **Step 3: Add the Bootstrap Icons CDN link**

In `app/views/layouts/application.html.erb`, replace:

```erb
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">
    <%= stylesheet_link_tag "application", "data-turbo-track": "reload" %>
```

with:

```erb
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.3/font/bootstrap-icons.min.css" rel="stylesheet">
    <%= stylesheet_link_tag "application", "data-turbo-track": "reload" %>
```

- [ ] **Step 4: Fix the archive button partial**

Replace the entire content of `app/views/projects/_archive_button.html.erb`:

```erb
<%= form_with(model: project, local: true, method: :patch, style: "display:inline-block") do |f| %>
  <%= f.hidden_field :status, value: "archived" %>
  <%= f.submit "Archivar", class: "btn btn-outline-danger btn-sm" %>
<% end %>
```

with:

```erb
<%= form_with(model: project, local: true, method: :patch, html: { class: "d-inline" }) do |f| %>
  <%= f.hidden_field :status, value: "archived" %>
  <%= f.button type: "submit", class: "btn btn-outline-danger btn-sm" do %>
    <i class="bi bi-archive"></i> Archivar
  <% end %>
<% end %>
```

- [ ] **Step 5: Wrap the Listado table's action buttons in a flex container**

In `app/views/projects/_project_type_section.html.erb`, replace:

```erb
              <td>
                <%= link_to "Editar", edit_project_path(project), class: "btn btn-outline-secondary btn-sm" %>
                <%= render "archive_button", project: project %>
              </td>
```

with:

```erb
              <td>
                <div class="d-flex gap-2">
                  <%= link_to edit_project_path(project), class: "btn btn-outline-secondary btn-sm" do %>
                    <i class="bi bi-pencil"></i> Editar
                  <% end %>
                  <%= render "archive_button", project: project %>
                </div>
              </td>
```

- [ ] **Step 6: Add the icon to `show`'s Editar link**

In `app/views/projects/show.html.erb`, replace:

```erb
    <%= link_to "Editar", edit_project_path(@project), class: "btn btn-outline-secondary btn-sm" %>
```

with:

```erb
    <%= link_to edit_project_path(@project), class: "btn btn-outline-secondary btn-sm" do %>
      <i class="bi bi-pencil"></i> Editar
    <% end %>
```

- [ ] **Step 7: Update the 2 pre-existing tests that assert on the old `<input>` markup**

In `test/controllers/projects_controller_test.rb`, replace (around line 80-88):

```ruby
  test "show displays a status badge and an archive button" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_path(project)
    assert_response :success
    assert_select "span.badge.bg-success", "Activo"
    assert_select "form[action=?]", project_path(project) do
      assert_select "input[value=?]", "Archivar"
    end
  end
```

with:

```ruby
  test "show displays a status badge and an archive button" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_path(project)
    assert_response :success
    assert_select "span.badge.bg-success", "Activo"
    assert_select "form[action=?]", project_path(project) do
      assert_select "button", text: /Archivar/
    end
  end
```

And replace (around line 391-397):

```ruby
  test "index shows an archive button for each project" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get projects_path
    assert_select "form[action=?]", project_path(project) do
      assert_select "input[value=?]", "Archivar"
    end
  end
```

with:

```ruby
  test "index shows an archive button for each project" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get projects_path
    assert_select "form[action=?]", project_path(project) do
      assert_select "button", text: /Archivar/
    end
  end
```

- [ ] **Step 8: Run the full test file to verify everything passes**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: all PASS.

- [ ] **Step 9: Run the full suite to check for regressions elsewhere**

Run: `bin/rails test`
Expected: all PASS.

- [ ] **Step 10: Commit**

```bash
git add app/views/layouts/application.html.erb app/views/projects/_archive_button.html.erb \
  app/views/projects/_project_type_section.html.erb app/views/projects/show.html.erb \
  test/controllers/projects_controller_test.rb
git commit -m "Fix Archivar button alignment bug, add icons to Editar/Archivar buttons"
```

---

## Final Verification

- [ ] Run the full test suite: `bin/rails test`
- [ ] Expected: all tests pass, no regressions anywhere else in the app.
