# Pulido de los formularios Nuevo/Editar proyecto — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring `projects#new`/`#edit` in line with the rest of the app's visual pattern — card-wrapped form, context in the title, and a "Cancelar" link — without touching the dynamic field inputs, which already work and already match the app's form-control styling.

**Architecture:** Pure view-layer change across 3 small ERB files. No controller/model/route changes.

**Tech Stack:** Ruby on Rails, Minitest, Bootstrap `.card` (already used elsewhere, no new CSS).

## Global Constraints

- No changes to `app/views/projects/_field_input.html.erb`, `app/controllers/projects_controller.rb`, or any model.
- `project.persisted?` decides where "Cancelar" goes (`project_path` if editing an existing project, `projects_path` if it's a new one) — no controller change needed for this, it's a plain Ruby check already available in the view via the `project` local.

---

### Task 1: Card, context title, cancel link for new/edit

**Files:**
- Modify: `app/views/projects/new.html.erb`
- Modify: `app/views/projects/edit.html.erb`
- Modify: `app/views/projects/_form.html.erb`
- Modify: `test/controllers/projects_controller_test.rb`

**Interfaces:**
- Consumes: `Project#persisted?` (ActiveRecord built-in, unchanged).
- Produces: nothing consumed by a later task — this is the only task in this plan.

- [ ] **Step 1: Write the failing tests**

Add to `test/controllers/projects_controller_test.rb`, inside the existing test class:

```ruby
  test "new shows the project type in the title, wraps the form in a card, and links Cancelar to the list" do
    get new_project_path(project_type_id: project_types(:instalaciones).id)
    assert_response :success
    assert_select "h1", /Instalaciones/
    assert_select ".card form"
    assert_select "a[href=?]", projects_path, text: "Cancelar"
  end

  test "edit shows the project name in the title, wraps the form in a card, and links Cancelar to the project" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get edit_project_path(project)
    assert_response :success
    assert_select "h1", /Torre Norte/
    assert_select ".card form"
    assert_select "a[href=?]", project_path(project), text: "Cancelar"
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: FAIL — `edit`'s `<h1>` doesn't include the project name yet, and neither page has a `.card`-wrapped form or a "Cancelar" link yet.

- [ ] **Step 3: Update `new.html.erb`**

Replace `app/views/projects/new.html.erb` in full:

```erb
<h1>Nuevo proyecto — <%= @project_type.name %></h1>
<div class="card">
  <div class="card-body">
    <%= render "form", project: @project, project_type: @project_type %>
  </div>
</div>
```

- [ ] **Step 4: Update `edit.html.erb`**

Replace `app/views/projects/edit.html.erb` in full:

```erb
<h1>Editar proyecto — <%= @project.name %></h1>
<div class="card">
  <div class="card-body">
    <%= render "form", project: @project, project_type: @project_type %>
  </div>
</div>
```

- [ ] **Step 5: Add the Cancelar link to `_form.html.erb`**

Edit `app/views/projects/_form.html.erb` — replace the last line:

```erb
  <%= form.submit class: "btn btn-primary" %>
<% end %>
```

with:

```erb
  <%= form.submit class: "btn btn-primary" %>
  <%= link_to "Cancelar", project.persisted? ? project_path(project) : projects_path, class: "btn btn-outline-secondary" %>
<% end %>
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: PASS (all tests)

- [ ] **Step 7: Run the full suite**

Run: `bin/rails test`
Expected: PASS

- [ ] **Step 8: Manual verification**

Run: `bin/rails server`:
- Go to "Proyectos" → click a project type to create a new project — confirm the title shows the type, the form is inside a card, and "Cancelar" goes back to the projects list.
- Edit an existing project — confirm the title shows the project's name, the form is inside a card, and "Cancelar" goes back to that project's detail page.

- [ ] **Step 9: Commit**

```bash
git add app/views/projects/new.html.erb app/views/projects/edit.html.erb app/views/projects/_form.html.erb \
  test/controllers/projects_controller_test.rb
git commit -m "Polish project new/edit forms: card, context title, Cancelar link"
```

---

## Final verification

- [ ] Run `bin/rails test` once more — expect a clean pass.
