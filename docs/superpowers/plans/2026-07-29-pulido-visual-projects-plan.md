# Pulido visual de las pantallas de Proyectos Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the app's existing visual theme (navy `#2c3e50`, rounded corners, card shadows, `admin_card` helper — already applied to login and `/admin/*`) to the remaining `projects/*` views, and add a color legend under every Gantt chart that colors its bars by something.

**Architecture:** Pure view/CSS-layer changes. `admin_card` is renamed to `panel_card` (mechanical, same output) and reused in `projects/new`/`edit`/the filter card. A new tiny partial renders a color-swatch legend, fed by data the two Gantt-rendering views already compute.

**Tech Stack:** Rails 7.2, Minitest with fixtures, Bootstrap (no new dependency).

## Global Constraints

- No DB/model/migration changes. No new JS/CSS dependency.
- `/projects/seguimiento` (tracker) is **not** touched at all — it deliberately has no cards (Excel-style dense look), protected by `test "tracker renders each project's data as a graphite band without a bordered card"` (`assert_select ".card", count: 0`). Do not add cards there.
- `admin_card` → `panel_card` is a pure rename (identical generated HTML) — no test that asserts on rendered markup should need to change because of the rename itself.

---

### Task 1: Rename `admin_card` → `panel_card`, use it in `projects/new`/`edit`/filters, theme the tabs

**Files:**
- Modify: `app/helpers/application_helper.rb`
- Modify: `app/views/admin/field_definitions/_form.html.erb`
- Modify: `app/views/admin/users/index.html.erb`
- Modify: `app/views/admin/responsible_types/_form.html.erb`
- Modify: `app/views/admin/responsibles/_form.html.erb`
- Modify: `app/views/admin/users/_form.html.erb`
- Modify: `app/views/admin/project_types/_form.html.erb`
- Modify: `app/views/admin/responsibles/index.html.erb`
- Modify: `app/views/admin/stage_templates/_form.html.erb`
- Modify: `app/views/admin/project_types/index.html.erb`
- Modify: `app/views/admin/log_entry_types/_form.html.erb`
- Modify: `app/views/projects/new.html.erb`
- Modify: `app/views/projects/edit.html.erb`
- Modify: `app/views/projects/_project_type_section.html.erb`
- Modify: `app/assets/stylesheets/application.css`
- Modify: `test/controllers/projects_controller_test.rb`

**Interfaces:**
- Produces: `ApplicationHelper#panel_card(title, &block)` (replaces `admin_card`).

- [ ] **Step 1: Write the failing tests**

In `test/controllers/projects_controller_test.rb`, find these two existing tests and change their `h1` assertion to a `.card-header` assertion (everything else in each test stays the same):

```ruby
  test "new shows the project type in the title, wraps the form in a card, and links Cancelar to the list" do
    get new_project_path(project_type_id: project_types(:instalaciones).id)
    assert_response :success
    assert_select ".card-header", /Instalaciones/
    assert_select ".card form"
    assert_select "a[href=?]", projects_path, text: "Cancelar"
  end

  test "edit shows the project name in the title, wraps the form in a card, and links Cancelar to the project" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get edit_project_path(project)
    assert_response :success
    assert_select ".card-header", /Torre Norte/
    assert_select ".card form"
    assert_select "a[href=?]", project_path(project), text: "Cancelar"
  end
```

Add a new test for the filter card's title:

```ruby
  test "index's filter card has a Filtros title" do
    get project_type_projects_path(project_types(:instalaciones).slug)
    assert_response :success
    assert_select ".card-header", "Filtros"
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n "/new shows the project type|edit shows the project name|filter card has a Filtros title/"`
Expected: FAIL — `h1` still present (for the first two), no `.card-header` with "Filtros" yet (for the third).

- [ ] **Step 3: Rename the helper**

In `app/helpers/application_helper.rb`, rename `admin_card` to `panel_card` (identical body):

```ruby
  def panel_card(title, &block)
    content_tag(:div, class: "card mb-4") do
      content_tag(:div, title, class: "card-header fw-semibold") +
        content_tag(:div, capture(&block), class: "card-body")
    end
  end
```

- [ ] **Step 4: Update every call site**

In each of these 11 files, replace `admin_card(` with `panel_card(` (single occurrence per file, no other change):

- `app/views/admin/field_definitions/_form.html.erb`
- `app/views/admin/users/index.html.erb`
- `app/views/admin/responsible_types/_form.html.erb`
- `app/views/admin/responsibles/_form.html.erb`
- `app/views/admin/users/_form.html.erb`
- `app/views/admin/project_types/_form.html.erb`
- `app/views/admin/responsibles/index.html.erb`
- `app/views/admin/stage_templates/_form.html.erb`
- `app/views/admin/project_types/index.html.erb`
- `app/views/admin/log_entry_types/_form.html.erb`

- [ ] **Step 5: Wrap `projects/new.html.erb` and `edit.html.erb` in `panel_card`**

Replace the full contents of `app/views/projects/new.html.erb`:

```erb
<%= panel_card("Nuevo proyecto — #{@project_type.name}") do %>
  <%= render "form", project: @project, project_type: @project_type %>
<% end %>
```

Replace the full contents of `app/views/projects/edit.html.erb`:

```erb
<%= panel_card("Editar proyecto — #{@project.name}") do %>
  <%= render "form", project: @project, project_type: @project_type %>
<% end %>
```

- [ ] **Step 6: Wrap the filter form in `_project_type_section.html.erb` with a titled `panel_card`**

Replace:

```erb
<div class="card mb-4">
  <div class="card-body">
    <%= form_with url: project_type_projects_path(slug), method: :get, local: true, class: "row g-2" do |form| %>
      ...
    <% end %>
  </div>
</div>
```

with:

```erb
<%= panel_card("Filtros") do %>
  <%= form_with url: project_type_projects_path(slug), method: :get, local: true, class: "row g-2" do |form| %>
    ...
  <% end %>
<% end %>
```

(Keep everything between the `form_with do |form|` and its matching `<% end %>` exactly as it is today — only the surrounding `<div class="card">...</div>` wrapper changes to `panel_card`.)

- [ ] **Step 7: Theme the active tab**

In `app/assets/stylesheets/application.css`, add at the end:

```css
.nav-tabs .nav-link.active {
  color: var(--bs-primary);
  border-color: rgba(0, 0, 0, 0.06) rgba(0, 0, 0, 0.06) #fff;
  font-weight: 600;
}
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: PASS

- [ ] **Step 9: Run the full suite**

Run: `bin/rails test`
Expected: PASS — every `/admin/*` controller test that asserts on `.card`/`.card-header` markup still passes unchanged (the rename produces identical HTML), and `"tracker renders each project's data as a graphite band without a bordered card"` still passes (tracker untouched).

- [ ] **Step 10: Commit**

```bash
git add app/helpers/application_helper.rb app/views/admin app/views/projects/new.html.erb \
  app/views/projects/edit.html.erb app/views/projects/_project_type_section.html.erb \
  app/assets/stylesheets/application.css test/controllers/projects_controller_test.rb
git commit -m "Rename admin_card to panel_card and extend it to projects/new, edit, and filters"
```

---

### Task 2: Gantt color legend

**Files:**
- Create: `app/views/projects/_gantt_legend.html.erb`
- Modify: `app/views/projects/show.html.erb`
- Modify: `app/views/projects/_project_type_section.html.erb`
- Test: `test/controllers/projects_controller_test.rb`

**Interfaces:**
- Produces: `render "gantt_legend", entries: [[name, color], ...]` partial, reusable by any Gantt-rendering view.

- [ ] **Step 1: Write the failing tests**

Add to `test/controllers/projects_controller_test.rb`:

```ruby
  test "show's Gantt has a legend naming each stage_template's color" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    stage_templates(:produccion).update!(color: "#ff0000")

    get project_path(project)
    assert_response :success
    assert_select ".gantt-legend span", text: /Producción/
  end

  test "show's Gantt legend labels a stage with no stage_template as Sin subproceso" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    project.project_stages.first.update!(stage_template: nil)

    get project_path(project)
    assert_response :success
    assert_select ".gantt-legend span", text: /Sin subproceso/
  end

  test "index's Gantt legend appears only when a responsible type is selected" do
    slug = project_types(:instalaciones).slug
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    ProjectResponsible.create!(project: project, responsible: responsibles(:ana_gomez), responsible_type: responsible_types(:instalador))

    get project_type_projects_path(slug)
    assert_response :success
    assert_select ".gantt-legend", count: 0

    get project_type_projects_path(slug), params: { responsible_type_id: responsible_types(:instalador).id }
    assert_response :success
    assert_select ".gantt-legend span", text: /Ana Gómez/
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n "/Gantt has a legend|Gantt legend labels|Gantt legend appears only/"`
Expected: FAIL — no `.gantt-legend` element exists yet.

- [ ] **Step 3: Create the legend partial**

```erb
<%# app/views/projects/_gantt_legend.html.erb — locals: (entries:) %>
<div class="gantt-legend d-flex flex-wrap gap-3 mb-3">
  <% entries.each do |name, color| %>
    <span class="d-inline-flex align-items-center gap-1">
      <span class="rounded-circle d-inline-block" style="width: 0.75rem; height: 0.75rem; background-color: <%= color %>;"></span>
      <small><%= name %></small>
    </span>
  <% end %>
</div>
```

- [ ] **Step 4: Wire it into `projects/show.html.erb`**

Replace:

```ruby
  stage_colors = stages.map { |stage| [stage.stage_template_id || "none", stage.stage_template&.color || "#6c757d"] }.uniq
```

with:

```ruby
  stage_colors = stages.map { |stage| [stage.stage_template_id || "none", stage.stage_template&.name || "Sin subproceso", stage.stage_template&.color || "#6c757d"] }.uniq
```

Replace the CSS-building loop:

```erb
      <% stage_colors.each do |template_id, color| %>
```

with:

```erb
      <% stage_colors.each do |template_id, _name, color| %>
```

(its body — the `.gantt .bar-wrapper.stage-color-<%= template_id %> ...` rules — stays exactly as-is).

Add the legend right before the Gantt container:

```erb
    <%= render "gantt_legend", entries: stage_colors.map { |_, name, color| [name, color] } %>
    <div id="gantt" class="mb-4"></div>
```

- [ ] **Step 5: Wire it into `projects/_project_type_section.html.erb`**

Replace:

```ruby
    gantt_colors = if selected_type
      projects_list.map { |project| project.responsible_for(selected_type) }.compact.uniq.map { |r| [r.id, r.color] }
    else
      []
    end
```

with:

```ruby
    gantt_colors = if selected_type
      projects_list.map { |project| project.responsible_for(selected_type) }.compact.uniq.map { |r| [r.id, r.name, r.color] }
    else
      []
    end
```

Replace the CSS-building loop:

```erb
        <% gantt_colors.each do |responsible_id, color| %>
```

with:

```erb
        <% gantt_colors.each do |responsible_id, _name, color| %>
```

(its body stays exactly as-is).

Add the legend right before the Gantt container, only when there's something to show:

```erb
      <% if selected_type && gantt_colors.any? %>
        <%= render "gantt_legend", entries: gantt_colors.map { |_, name, color| [name, color] } %>
      <% end %>
      <div id="gantt-<%= slug %>" class="mb-0"></div>
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: PASS

- [ ] **Step 7: Run the full suite**

Run: `bin/rails test`
Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add app/views/projects/_gantt_legend.html.erb app/views/projects/show.html.erb \
  app/views/projects/_project_type_section.html.erb test/controllers/projects_controller_test.rb
git commit -m "Add a color legend under each Gantt that colors its bars"
```
