# Proyectos por tipo (navegación en pestañas) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single `/projects` page that stacks every `ProjectType` in an accordion (computing filters/Gantt/pagination for all types on every request) with one page per type, reachable via tabs with their own URL (`/projects/tipo/:slug`), loading only that type's data.

**Architecture:** One new route (`/projects/tipo/:slug`), `ProjectsController#index` resolves a single `ProjectType` from the slug (or redirects to a canonical one), and reuses the existing `build_section` method — now reading flat `params` instead of `params[:sections][slug]`. The view swaps the Bootstrap accordion for `nav-tabs`. No model, migration, or business-logic (filtering, Gantt, bulk-assign, permissions) changes — purely routing/controller/view.

**Tech Stack:** Rails 7.2, Minitest with fixtures, Bootstrap `nav-tabs` (replacing `accordion`).

## Global Constraints

- No DB/model changes. No new dependency.
- `/projects/seguimiento` (tracker) is untouched — it already solves the same problem with its own dropdown.
- Every DOM id currently suffixed with `<%= slug %>` (`#gantt-<%= slug %>`, `#bulk-assign-form-<%= slug %>`, `#select-all-projects-<%= slug %>`, `#view-mode-<%= slug %>`) stays suffixed, to minimize the diff on the existing inline JS — even though only one section renders per page now.
- The filter form's field ids change from `sections_<%= slug %>_<field>` to plain `<field>` (e.g. `status`, `stage_name`, `responsible_type_id`) because the `form_with ... scope: "sections[#{slug}]"` wrapper is removed — every test asserting on those ids must be updated accordingly.

---

### Task 1: Per-type route, controller, view, and full test migration

**Files:**
- Modify: `config/routes.rb`
- Modify: `app/controllers/projects_controller.rb`
- Modify: `app/views/projects/index.html.erb`
- Modify: `app/views/projects/_project_type_section.html.erb`
- Modify: `test/controllers/projects_controller_test.rb`

**Interfaces:**
- Produces: `project_type_projects_path(slug)` route helper, `ProjectsController#index` resolving `@project_type`/`@project_types`/`@section` (replacing `@sections`).

This is one atomic task — the route, controller, two views, and every affected test must land together, since a partial change leaves the page non-functional (old view expects `@sections`, new controller only provides `@section`).

- [ ] **Step 1: Add the route**

In `config/routes.rb`, add right above `resources :projects do`:

```ruby
  get "projects/tipo/:slug", to: "projects#index", as: :project_type_projects
```

- [ ] **Step 2: Rewrite `ProjectsController#index` and `build_section`**

Replace the `index` action:

```ruby
  def index
    @project_type = ProjectType.find_by(slug: params[:slug]) || ProjectType.first
    return render(:index) if @project_type.nil?
    return redirect_to(project_type_projects_path(@project_type.slug)) if params[:slug].blank? || params[:slug] != @project_type.slug

    @project_types = ProjectType.all
    @statuses = Project.distinct.pluck(:status).compact
    @section = build_section(@project_type)
  end
```

(`params[:slug] != @project_type.slug` covers a slug in the URL that doesn't match any `ProjectType` — falls back to `ProjectType.first` and redirects to its canonical URL, same as no slug at all. `@project_type.nil?` — no `ProjectType` configured at all — renders `index` directly with `@project_type` nil, no redirect loop.)

Replace `build_section`:

```ruby
  def build_section(project_type)
    filtered = params.key?(:status)

    projects = Project.visible_to(current_user).where(project_type: project_type).includes(:project_type, project_stages: :stage_template).order(:name)
    projects = params[:status].present? ? projects.where(status: params[:status]) : projects.where.not(status: "archived")
    projects = filter_by_responsible(projects, params[:responsible_type_id], params[:responsible_id])
    projects = filter_by_date_range(projects, params[:from_date], params[:to_date])
    projects = filter_by_query(projects, params[:q])

    projects_list = projects.to_a
    per_page = 20
    page = [params[:page].to_i, 1].max
    total_pages = (projects_list.size / per_page.to_f).ceil
    page_projects = projects_list.drop((page - 1) * per_page).first(per_page)
    stage_names = StageTemplate.where(project_type: project_type).order(:name).pluck(:name)

    stage_name = if filtered
      params[:stage_name]
    else
      project_type.stage_templates.find_by(default_in_filter: true)&.name
    end

    {
      project_type: project_type,
      params: params.slice(:status, :responsible_type_id, :responsible_id, :from_date, :to_date, :stage_name, :q, :page),
      stage_name: stage_name,
      projects_list: projects_list,
      page_projects: page_projects,
      page: page,
      total_pages: total_pages,
      stage_names: stage_names
    }
  end
```

(`params.key?(:status)` is the new "was the filter form ever submitted" signal, replacing the old `section_submitted.nil?` check on the `sections[slug]` wrapper key — the filter form always includes a `status` field, even blank, once submitted, so its mere presence in `params` distinguishes "fresh navigation to this tab" from "form submitted with everything cleared.")

- [ ] **Step 3: Rewrite `app/views/projects/index.html.erb`**

```erb
<div class="d-flex justify-content-between align-items-center mb-3">
  <h1 class="mb-0">Proyectos</h1>
  <% if @project_type && (current_user.admin? || current_user.gerente?) %>
    <%= link_to "Nuevo proyecto", new_project_path(project_type_id: @project_type.id), class: "btn btn-primary" %>
  <% end %>
</div>

<% if @project_type.nil? %>
  <p>No hay tipos de proyecto configurados todavía.</p>
<% else %>
  <ul class="nav nav-tabs mb-4">
    <% @project_types.each do |project_type| %>
      <li class="nav-item">
        <%= link_to project_type.name, project_type_projects_path(project_type.slug),
              class: "nav-link #{"active" if project_type == @project_type}" %>
      </li>
    <% end %>
  </ul>

  <%= render "project_type_section", section: @section %>
<% end %>
```

- [ ] **Step 4: Update `_project_type_section.html.erb`**

Remove the `scope:` from the filter `form_with` — change:

```erb
    <%= form_with url: projects_path, method: :get, local: true, scope: "sections[#{slug}]", class: "row g-2" do |form| %>
```

to:

```erb
    <%= form_with url: project_type_projects_path(slug), method: :get, local: true, class: "row g-2" do |form| %>
```

Replace the "Quitar filtros" link:

```erb
        <%= link_to "Quitar filtros",
              projects_path(request.query_parameters.deep_merge(
                "sections" => { slug => { "status" => "", "responsible_type_id" => "", "responsible_id" => "", "from_date" => "", "to_date" => "", "stage_name" => "", "q" => "", "page" => "" } }
              )),
              class: "btn btn-outline-secondary" %>
```

with:

```erb
        <%= link_to "Quitar filtros", project_type_projects_path(slug), class: "btn btn-outline-secondary" %>
```

Replace the two pagination links and the "Anterior"/"Siguiente" links (all three `deep_merge("sections" => { slug => { "page" => ... } })` calls):

```erb
              <%= link_to "Anterior", projects_path(request.query_parameters.deep_merge("sections" => { slug => { "page" => section[:page] - 1 } })), class: "page-link" %>
```
```erb
                <%= link_to n, projects_path(request.query_parameters.deep_merge("sections" => { slug => { "page" => n } })), class: "page-link" %>
```
```erb
              <%= link_to "Siguiente", projects_path(request.query_parameters.deep_merge("sections" => { slug => { "page" => section[:page] + 1 } })), class: "page-link" %>
```

with:

```erb
              <%= link_to "Anterior", project_type_projects_path(slug, request.query_parameters.merge(page: section[:page] - 1)), class: "page-link" %>
```
```erb
                <%= link_to n, project_type_projects_path(slug, request.query_parameters.merge(page: n)), class: "page-link" %>
```
```erb
              <%= link_to "Siguiente", project_type_projects_path(slug, request.query_parameters.merge(page: section[:page] + 1)), class: "page-link" %>
```

Everything else in this partial (Gantt task/color computation, bulk-assign form, Listado table, all `<%= slug %>`-suffixed DOM ids) stays exactly as-is.

- [ ] **Step 5: Delete the tests that only make sense for the old multi-section-on-one-page architecture**

Remove these five tests entirely from `test/controllers/projects_controller_test.rb` — each one specifically tests that multiple `ProjectType` sections coexist on the same page without interfering, which is no longer a real scenario once each type has its own page (there is nothing left to interfere with):

- `"index shows each project type as its own section, listing only that type's own projects"`
- `"index's accordion expands the first section and collapses the rest"`
- `"index's filter for one section doesn't affect another section's results"`
- `"index's pagination for one section doesn't affect another section's page"`
- `"index's ids are unique per section (Gantt, bulk-assign form, select-all checkbox)"`

- [ ] **Step 6: Add new tests for the routing/redirect behavior**

Add these to `test/controllers/projects_controller_test.rb`:

```ruby
  test "index without a slug redirects to the first project type's tab" do
    get projects_path
    assert_redirected_to project_type_projects_path(ProjectType.first.slug)
  end

  test "index with an unknown slug redirects to the first project type's tab" do
    get project_type_projects_path("no-existe")
    assert_redirected_to project_type_projects_path(ProjectType.first.slug)
  end

  test "index with no ProjectType configured at all shows a message instead of erroring" do
    ProjectType.destroy_all
    get projects_path
    assert_response :success
    assert_select "body", /No hay tipos de proyecto configurados todavía/
  end

  test "index shows a tab for every project type, with the current one active" do
    other_type = ProjectType.create!(name: "Mantenimiento", slug: "mantenimiento")
    get project_type_projects_path(project_types(:instalaciones).slug)
    assert_response :success
    assert_select "a.nav-link.active", text: project_types(:instalaciones).name
    assert_select "a.nav-link", text: other_type.name
  end
```

(`ProjectType.destroy_all` in the third test only works if no `Project`/`FieldDefinition`/etc. rows reference it — this test runs against the default fixture set with no projects created for `project_types(:instalaciones)`, but `ProjectType` itself is referenced by other fixtures like `stage_templates`/`field_definitions`/`responsible_types`, which cascade-destroy via their own `dependent: :destroy`/`restrict_with_error` associations already in place — if `destroy_all` raises here, use `ProjectType.delete_all` instead, since this test only needs the `ProjectType` table to end up empty, not to exercise any specific destroy-time validation.)

- [ ] **Step 7: Convert every remaining test in the file from the nested `sections[slug]` scheme to the new flat one**

Go through `test/controllers/projects_controller_test.rb` and apply these four mechanical transformations everywhere they appear (search case-sensitively for `sections`, `projects_path`, and `#sections_` to find every remaining site — there are roughly 35 more call sites beyond what Steps 5-6 already handled):

1. **Bare `get projects_path` that expects to render index content directly** (not testing the redirect itself) → `get project_type_projects_path(project_types(:instalaciones).slug)`. This applies to every test that calls `get projects_path` with no `params:` and then asserts on the rendered body/response — since `projects_path` (no slug) now 302-redirects instead of rendering, these need the canonical per-type URL directly.

2. **`get projects_path, params: { sections: { slug => { KEY: VALUE, ... } } }`** → `get project_type_projects_path(slug), params: { KEY: VALUE, ... }` (drop the `sections`/slug nesting, keep the inner hash as top-level params).

3. **Field id/name assertions** — the filter form no longer has a `scope`, so field ids/names are unprefixed:
   - `assert_select "select#sections_#{slug}_status ..."` → `assert_select "select#status ..."`
   - `assert_select "select#sections_#{slug}_stage_name ..."` → `assert_select "select#stage_name ..."`
   - `assert_select "select#sections_#{slug}_responsible_type_id"` → `assert_select "select#responsible_type_id"`
   - `assert_select "select#sections_#{slug}_responsible_id"` → `assert_select "select#responsible_id"`
   - `assert_select "input[type=date][name=?]", "sections[#{slug}][from_date]"` → `assert_select "input[type=date][name=?]", "from_date"` (same for `to_date`)
   - `assert_select "input[type=text][name=?]", "sections[#{slug}][q]"` → `assert_select "input[type=text][name=?]", "q"`

4. **Pagination link assertions** — `assert_select "a.page-link[href=?]", projects_path(sections: { slug => { page: N } })` → `assert_select "a.page-link[href=?]", project_type_projects_path(slug, page: N)` (and the same pattern with additional keys alongside `page:`, e.g. `status: "active", page: 2` — keep every key, just flatten it: `project_type_projects_path(slug, status: "active", page: 2)`).

Two tests need special care beyond the mechanical rules above:

**`"index shows a Quitar filtros link that explicitly blanks every field for that section"`** — rewrite its body (the link no longer carries any query params at all, since "Quitar filtros" now just points at the bare tab URL):

```ruby
  test "index shows a Quitar filtros link that points at the bare tab URL" do
    slug = project_types(:instalaciones).slug
    get project_type_projects_path(slug), params: { status: "archived", q: "algo" }
    assert_response :success
    assert_select "a[href=?]", project_type_projects_path(slug), text: "Quitar filtros"
  end
```

**`"index's Etapa filter doesn't apply the default when the section was explicitly filtered with Etapa left blank"`** — this test's params already include `status: ""` alongside `stage_name: ""`, which is exactly what makes `params.key?(:status)` true in the new `build_section` — just flatten its params per rule 2 (`params: { stage_name: "", status: "" }` with no `sections` wrapper), no other change needed; it should pass unchanged in behavior.

- [ ] **Step 8: Run tests to verify they pass**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: PASS

- [ ] **Step 9: Verify no stray `sections[` references remain**

Run: `grep -n "sections\[" app/views/projects/*.erb test/controllers/projects_controller_test.rb`
Expected: no output. If anything prints, it's a missed conversion from Step 7 — fix it.

- [ ] **Step 10: Run the full suite**

Run: `bin/rails test`
Expected: PASS, no regressions elsewhere (the `tracker` action/view, `imports`, and every other controller are untouched by this task).

- [ ] **Step 11: Commit**

```bash
git add config/routes.rb app/controllers/projects_controller.rb app/views/projects/index.html.erb \
  app/views/projects/_project_type_section.html.erb test/controllers/projects_controller_test.rb
git commit -m "Split the projects index into one tabbed page per project type"
```
