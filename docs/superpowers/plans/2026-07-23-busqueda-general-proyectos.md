# Búsqueda general (LIKE) en projects#index — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user type a search term on `projects#index` that matches a project's name OR any value inside its dynamic `custom_fields`, regardless of which `ProjectType` it belongs to.

**Architecture:** One additive filter method in `ProjectsController`, following the exact same shape as the existing `filter_by_installer`/`filter_by_date_range` private methods, plus one new text field in the existing filter form. No schema changes, no new dependencies — a single `ILIKE` against `projects.name` and the jsonb column cast to text.

**Tech Stack:** Rails 7.2.3 controller/view code, Minitest integration tests, PostgreSQL `ILIKE` + `::text` jsonb cast.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-23-busqueda-general-proyectos-design.md`.
- The match is an OR internally (name OR custom_fields) — it combines with AND against the *other* existing filters (Tipo/Estado/Instalador/Desde-Hasta), same as every other filter in `index`.
- No resolution of the "instalador" field's stored ID to an installer name — searching by installer name is explicitly out of scope (the dedicated Instalador filter covers that).
- `q` blank/absent must behave exactly as today (no filtering by text).
- This plan only touches `projects#index` — `projects#tracker` (Seguimiento) is out of scope.

---

## File Structure

- Modify `app/controllers/projects_controller.rb` — add `filter_by_query` private method (next to `filter_by_date_range`) and its call in `index`.
- Modify `app/views/projects/index.html.erb` — add a `q` text field to the existing filters form.
- Modify `test/controllers/projects_controller_test.rb` — add tests for the new filter (existing file, same controller test suite used by every prior round on this screen).

---

### Task 1: General search filter (`q`)

**Files:**
- Modify: `app/controllers/projects_controller.rb:4-18` (the `index` action) and add a new private method near `filter_by_date_range` (currently ending at line 130).
- Modify: `app/views/projects/index.html.erb:17-45` (the filters form).
- Test: `test/controllers/projects_controller_test.rb`.

**Interfaces:**
- Consumes: `Project#name`, `Project#custom_fields` (jsonb column, existing).
- Produces: `ProjectsController#filter_by_query(scope, q)` — private method, takes an `ActiveRecord::Relation` of `Project` and a search string (may be blank), returns a relation. Used only within `index`; no other task depends on it (this is the only task in the plan).

- [ ] **Step 1: Write the failing tests**

Add to `test/controllers/projects_controller_test.rb` (near the other filter tests):

```ruby
  test "index's q filter matches a project by name" do
    match = Project.create!(project_type: project_types(:instalaciones), name: "Torre del Bosque", custom_fields: {})
    other = Project.create!(project_type: project_types(:instalaciones), name: "Otro Proyecto", custom_fields: {})

    get projects_path, params: { q: "Bosque" }
    assert_response :success
    assert_match(/#{match.name}/, response.body)
    assert_no_match(/#{other.name}/, response.body)
  end

  test "index's q filter matches a value inside custom_fields, regardless of which field holds it" do
    match = Project.create!(
      project_type: project_types(:instalaciones), name: "Proyecto A",
      custom_fields: { cliente: "Constructora Acme S.R.L." }
    )
    other = Project.create!(
      project_type: project_types(:instalaciones), name: "Proyecto B",
      custom_fields: { cliente: "Otro Cliente" }
    )

    get projects_path, params: { q: "Acme" }
    assert_response :success
    assert_match(/#{match.name}/, response.body)
    assert_no_match(/#{other.name}/, response.body)
  end

  test "index's q filter is case-insensitive" do
    project = Project.create!(
      project_type: project_types(:instalaciones), name: "Proyecto Mayúsculas",
      custom_fields: { cliente: "CONSTRUCTORA GRANDE" }
    )

    get projects_path, params: { q: "constructora grande" }
    assert_response :success
    assert_match(/#{project.name}/, response.body)
  end

  test "index's q filter combines with other filters (AND)" do
    other_type = ProjectType.create!(name: "Mantenimiento", slug: "mantenimiento")
    match = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    Project.create!(project_type: other_type, name: "Torre Norte", custom_fields: {})

    get projects_path, params: { q: "Torre Norte", project_type_id: project_types(:instalaciones).id }
    assert_response :success
    assert_select "a[href=?]", project_path(match)
    assert_equal 1, response.body.scan("Torre Norte").size
  end

  test "index shows no results when q doesn't match anything" do
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get projects_path, params: { q: "esto-no-existe-en-ningun-proyecto" }
    assert_response :success
    assert_select "body", /No hay proyectos con estos filtros/
  end

  test "index shows the q search field in the filter form" do
    get projects_path
    assert_response :success
    assert_select "input[type=text][name=?]", "q"
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n "/q filter|q search field/"`
Expected: FAIL — `params[:q]` is currently ignored entirely, and there's no `q` field in the form yet.

- [ ] **Step 3: Implement the controller filter**

In `app/controllers/projects_controller.rb`, add this line to `index`, right after the `filter_by_date_range` call:

```ruby
    @projects = filter_by_query(@projects, params[:q])
```

So `index` reads:

```ruby
  def index
    @project_types = ProjectType.all
    @statuses = Project.distinct.pluck(:status).compact
    @installers = Installer.all
    @projects = Project.includes(:project_type, project_stages: :stage_template).order(:name)
    @projects = params[:status].present? ? @projects.where(status: params[:status]) : @projects.where.not(status: "archived")
    @projects = @projects.where(project_type_id: params[:project_type_id]) if params[:project_type_id].present?
    if params[:installer_id] == "none"
      @projects = filter_by_no_installer(@projects)
    elsif params[:installer_id].present?
      @projects = filter_by_installer(@projects, params[:installer_id])
    end
    @projects = filter_by_date_range(@projects, params[:from_date], params[:to_date])
    @projects = filter_by_query(@projects, params[:q])
    @page = [params[:page].to_i, 1].max
  end
```

Add this private method directly after `filter_by_date_range` (which currently ends at line 130, right before the closing `end` of the class):

```ruby
  def filter_by_query(scope, q)
    return scope if q.blank?
    term = "%#{q}%"
    scope.where("projects.name ILIKE :term OR projects.custom_fields::text ILIKE :term", term: term)
  end
```

- [ ] **Step 4: Add the search field to the view**

In `app/views/projects/index.html.erb`, find the closing filter field before the "Filtrar" submit button — the Hasta date field, which ends with:

```erb
      <div class="col-auto">
        <%= form.label :to_date, "Hasta", class: "form-label" %>
        <%= form.date_field :to_date, value: params[:to_date], class: "form-control" %>
      </div>
      <div class="col-auto align-self-end">
        <%= form.submit "Filtrar", class: "btn btn-primary" %>
      </div>
```

Replace it with:

```erb
      <div class="col-auto">
        <%= form.label :to_date, "Hasta", class: "form-label" %>
        <%= form.date_field :to_date, value: params[:to_date], class: "form-control" %>
      </div>
      <div class="col-auto">
        <%= form.label :q, "Buscar", class: "form-label" %>
        <%= form.text_field :q, value: params[:q], class: "form-control", placeholder: "Nombre, cliente, dirección..." %>
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
git commit -m "Add general search filter (q) across project name and custom_fields"
```

---

## Final Verification

- [ ] Run the full test suite: `bin/rails test`
- [ ] Expected: all tests pass, no regressions anywhere else in the app.
