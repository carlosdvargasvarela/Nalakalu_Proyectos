# Etapa por defecto + botón "Quitar filtros" — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let an admin mark one `StageTemplate` per `ProjectType` as the default stage shown in that section's Etapa filter on first load, and add a "Quitar filtros" button that explicitly resets a section's filters to blank (never re-applying the default).

**Architecture:** Two mostly-independent pieces built in order: (1) a new `default_in_filter` boolean column + admin checkbox + a model callback enforcing "only one default per type", (2) `projects#index`'s per-section logic distinguishing "never filtered" (apply the default) from "filtered with Etapa left blank" (no filter), plus a reset link built the same way as the existing pagination links.

**Tech Stack:** Rails 7.2.3 migration/model/controller/view code, Minitest with fixtures.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-23-etapa-default-y-quitar-filtros-design.md`.
- Only one `StageTemplate` per `ProjectType` can have `default_in_filter: true` at a time — enforced by a model callback, not a DB constraint.
- "Quitar filtros" must reset **all** of a section's fields (Estado, Instalador, Etapa, Desde/Hasta, Buscar, página) to blank, and must NOT re-apply the configured default stage — it sends explicit blank values for `sections[<slug>]`, distinguishing itself from a truly fresh page load (no `sections[<slug>]` key at all).
- The default stage only applies on a genuinely fresh load of a section (no `sections[<slug>]` key present in the request at all).
- This plan only touches `projects#index` and the admin Subprocesos screens — `projects#tracker` (Seguimiento) is out of scope.
- No new gems, no new JS libraries.

---

## File Structure

- Create `db/migrate/YYYYMMDDHHMMSS_add_default_in_filter_to_stage_templates.rb`.
- Modify `app/models/stage_template.rb` — add the `clear_other_defaults` callback.
- Modify `app/controllers/admin/stage_templates_controller.rb` — permit `:default_in_filter`.
- Modify `app/views/admin/stage_templates/_form.html.erb` — add the checkbox.
- Modify `app/controllers/projects_controller.rb` — resolve the effective `stage_name` (default vs. explicit) in `build_section`.
- Modify `app/views/projects/_project_type_section.html.erb` — use the resolved `stage_name`, add the "Quitar filtros" link.
- Modify `test/models/stage_template_test.rb`, `test/controllers/admin/stage_templates_controller_test.rb`, `test/controllers/projects_controller_test.rb`.

---

### Task 1: `default_in_filter` column, model callback, admin checkbox

**Files:**
- Create: `db/migrate/YYYYMMDDHHMMSS_add_default_in_filter_to_stage_templates.rb`.
- Modify: `app/models/stage_template.rb`.
- Modify: `app/controllers/admin/stage_templates_controller.rb:39` (the `stage_template_params` private method).
- Modify: `app/views/admin/stage_templates/_form.html.erb`.
- Test: `test/models/stage_template_test.rb`, `test/controllers/admin/stage_templates_controller_test.rb`.

**Interfaces:**
- Produces: `StageTemplate#default_in_filter` (boolean column, default `false`), `StageTemplate#clear_other_defaults` (private callback, no external callers). Task 2 depends on the column existing and the "only one default per type" guarantee it provides — nothing else from this task.

- [ ] **Step 1: Write the failing model tests**

Add to `test/models/stage_template_test.rb`:

```ruby
  test "default_in_filter defaults to false" do
    stage = StageTemplate.new(project_type: project_types(:instalaciones), name: "Producción", position: 3)
    assert_equal false, stage.default_in_filter
  end

  test "marking one stage_template as default_in_filter clears any previous default in the same project_type" do
    entrega = stage_templates(:entrega)
    instalacion = stage_templates(:instalacion)

    entrega.update!(default_in_filter: true)
    assert entrega.reload.default_in_filter

    instalacion.update!(default_in_filter: true)
    assert instalacion.reload.default_in_filter
    assert_not entrega.reload.default_in_filter
  end

  test "marking a stage_template as default_in_filter doesn't affect a different project_type's default" do
    other_type = ProjectType.create!(name: "Mantenimiento", slug: "mantenimiento")
    other_stage = other_type.stage_templates.create!(name: "Revisión", position: 1, default_in_filter: true)

    stage_templates(:entrega).update!(default_in_filter: true)

    assert other_stage.reload.default_in_filter
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/models/stage_template_test.rb -n "/default_in_filter/"`
Expected: FAIL — `NoMethodError: undefined method 'default_in_filter'` (column doesn't exist yet).

- [ ] **Step 3: Create the migration**

Create `db/migrate/20260724000000_add_default_in_filter_to_stage_templates.rb`:

```ruby
class AddDefaultInFilterToStageTemplates < ActiveRecord::Migration[7.2]
  def change
    add_column :stage_templates, :default_in_filter, :boolean, default: false, null: false
  end
end
```

Run: `bin/rails db:migrate`
Expected: migration runs successfully, `db/schema.rb` now shows `t.boolean "default_in_filter", default: false, null: false` on `stage_templates`.

- [ ] **Step 4: Add the model callback**

In `app/models/stage_template.rb`, replace:

```ruby
class StageTemplate < ApplicationRecord
  belongs_to :project_type

  validates :name, presence: true
  validates :color, format: { with: /\A#[0-9a-fA-F]{6}\z/, message: "debe ser un color hexadecimal (ej. #6c757d)" }
end
```

with:

```ruby
class StageTemplate < ApplicationRecord
  belongs_to :project_type

  validates :name, presence: true
  validates :color, format: { with: /\A#[0-9a-fA-F]{6}\z/, message: "debe ser un color hexadecimal (ej. #6c757d)" }

  before_save :clear_other_defaults, if: :default_in_filter?

  private

  def clear_other_defaults
    project_type.stage_templates.where.not(id: id).update_all(default_in_filter: false)
  end
end
```

- [ ] **Step 5: Run the model tests to verify they pass**

Run: `bin/rails test test/models/stage_template_test.rb`
Expected: all PASS.

- [ ] **Step 6: Write the failing admin controller test**

Add to `test/controllers/admin/stage_templates_controller_test.rb`:

```ruby
  test "update saves default_in_filter and clears the previous default" do
    entrega = stage_templates(:entrega)
    instalacion = stage_templates(:instalacion)
    entrega.update!(default_in_filter: true)

    patch admin_project_type_stage_template_path(@project_type, instalacion), params: {
      stage_template: { name: instalacion.name, position: instalacion.position, default_in_filter: "1" }
    }

    assert_redirected_to admin_project_type_path(@project_type)
    assert instalacion.reload.default_in_filter
    assert_not entrega.reload.default_in_filter
  end

  test "new and edit show the Etapa por defecto checkbox" do
    get new_admin_project_type_stage_template_path(@project_type)
    assert_response :success
    assert_select "input[type=checkbox][name=?]", "stage_template[default_in_filter]"
  end
```

- [ ] **Step 7: Run the admin tests to verify they fail**

Run: `bin/rails test test/controllers/admin/stage_templates_controller_test.rb -n "/default_in_filter|Etapa por defecto/"`
Expected: FAIL — `default_in_filter` isn't permitted yet, and the checkbox doesn't exist in the form yet.

- [ ] **Step 8: Permit the param and add the checkbox**

In `app/controllers/admin/stage_templates_controller.rb`, replace:

```ruby
  def stage_template_params
    params.require(:stage_template).permit(:name, :position, :color)
  end
```

with:

```ruby
  def stage_template_params
    params.require(:stage_template).permit(:name, :position, :color, :default_in_filter)
  end
```

In `app/views/admin/stage_templates/_form.html.erb`, replace:

```erb
  <div class="mb-3">
    <%= form.label :color, class: "form-label" %>
    <%= form.color_field :color, class: "form-control form-control-color" %>
  </div>
  <%= form.submit class: "btn btn-primary" %>
```

with:

```erb
  <div class="mb-3">
    <%= form.label :color, class: "form-label" %>
    <%= form.color_field :color, class: "form-control form-control-color" %>
  </div>
  <div class="mb-3 form-check">
    <%= form.check_box :default_in_filter, class: "form-check-input" %>
    <%= form.label :default_in_filter, "Etapa por defecto en el filtro", class: "form-check-label" %>
  </div>
  <%= form.submit class: "btn btn-primary" %>
```

- [ ] **Step 9: Run the admin tests to verify they pass**

Run: `bin/rails test test/controllers/admin/stage_templates_controller_test.rb`
Expected: all PASS.

- [ ] **Step 10: Commit**

```bash
git add db/migrate/20260724000000_add_default_in_filter_to_stage_templates.rb db/schema.rb \
  app/models/stage_template.rb app/controllers/admin/stage_templates_controller.rb \
  app/views/admin/stage_templates/_form.html.erb \
  test/models/stage_template_test.rb test/controllers/admin/stage_templates_controller_test.rb
git commit -m "Add default_in_filter to StageTemplate, admin-editable, one default per type"
```

---

### Task 2: Default stage in `/projects` + "Quitar filtros" button

**Files:**
- Modify: `app/controllers/projects_controller.rb:1-19` (`build_section`, private method).
- Modify: `app/views/projects/_project_type_section.html.erb` (the Etapa `<select>`, the `gantt_tasks` block, and the filter form's submit row).
- Test: `test/controllers/projects_controller_test.rb`.

**Interfaces:**
- Consumes: `StageTemplate#default_in_filter` (from Task 1).
- Produces: `build_section`'s returned hash gains a `:stage_name` key (the *resolved* stage name — either the explicit filter value or the type's default) alongside the existing `:params` key (still the raw, unresolved params). Nothing else in the plan consumes this — it's the last task.

- [ ] **Step 1: Write the failing tests**

Add to `test/controllers/projects_controller_test.rb`:

```ruby
  test "index's Etapa filter uses the configured default stage on a fresh, unfiltered load" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    stage = project.project_stages.find_by(name: "Instalación")
    stage.update!(start_date: Date.new(2026, 9, 1), end_date: Date.new(2026, 9, 10))
    stage_templates(:instalacion).update!(default_in_filter: true)
    slug = project_types(:instalaciones).slug

    get projects_path
    assert_response :success
    assert_select "select#sections_#{slug}_stage_name option[selected]", "Instalación"
    assert_select "script#gantt-tasks-#{slug}" do |elements|
      tasks = JSON.parse(elements.first.text)
      task = tasks.find { |t| t["id"] == project.id.to_s }
      assert_equal "2026-09-01", task["start"]
      assert_equal "2026-09-10", task["end"]
    end
  end

  test "index's Etapa filter doesn't apply the default when the section was explicitly filtered with Etapa left blank" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    stage_templates(:instalacion).update!(default_in_filter: true)
    slug = project_types(:instalaciones).slug

    get projects_path, params: { sections: { slug => { stage_name: "", status: "" } } }
    assert_response :success
    assert_select "script#gantt-tasks-#{slug}" do |elements|
      tasks = JSON.parse(elements.first.text)
      task = tasks.find { |t| t["id"] == project.id.to_s }
      first, last = project.gantt_window
      assert_equal first.to_s, task["start"]
      assert_equal last.to_s, task["end"]
    end
  end

  test "index without any default stage configured behaves exactly as before" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    slug = project_types(:instalaciones).slug

    get projects_path
    assert_response :success
    assert_select "script#gantt-tasks-#{slug}" do |elements|
      tasks = JSON.parse(elements.first.text)
      task = tasks.find { |t| t["id"] == project.id.to_s }
      first, last = project.gantt_window
      assert_equal first.to_s, task["start"]
      assert_equal last.to_s, task["end"]
    end
  end

  test "index shows a Quitar filtros link that explicitly blanks every field for that section" do
    slug = project_types(:instalaciones).slug
    get projects_path
    assert_response :success
    assert_select "a", text: "Quitar filtros" do |elements|
      href = elements.first["href"]
      uri = URI.parse(href)
      params = Rack::Utils.parse_nested_query(uri.query)
      assert_equal "", params["sections"][slug]["status"]
      assert_equal "", params["sections"][slug]["installer_id"]
      assert_equal "", params["sections"][slug]["stage_name"]
      assert_equal "", params["sections"][slug]["from_date"]
      assert_equal "", params["sections"][slug]["to_date"]
      assert_equal "", params["sections"][slug]["q"]
    end
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n "/default stage|Quitar filtros/"`
Expected: FAIL — the default stage isn't applied yet, and the "Quitar filtros" link doesn't exist yet.

- [ ] **Step 3: Resolve the effective stage name in the controller**

In `app/controllers/projects_controller.rb`, replace:

```ruby
  def build_section(project_type)
    section_params = params.dig(:sections, project_type.slug) || {}

    projects = Project.where(project_type: project_type).includes(:project_type, project_stages: :stage_template).order(:name)
    projects = section_params[:status].present? ? projects.where(status: section_params[:status]) : projects.where.not(status: "archived")
    if section_params[:installer_id] == "none"
      projects = filter_by_no_installer(projects)
    elsif section_params[:installer_id].present?
      projects = filter_by_installer(projects, section_params[:installer_id])
    end
    projects = filter_by_date_range(projects, section_params[:from_date], section_params[:to_date])
    projects = filter_by_query(projects, section_params[:q])

    projects_list = projects.to_a
    per_page = 20
    page = [section_params[:page].to_i, 1].max
    total_pages = (projects_list.size / per_page.to_f).ceil
    page_projects = projects_list.drop((page - 1) * per_page).first(per_page)
    stage_names = StageTemplate.where(project_type: project_type).order(:name).pluck(:name)

    {
      project_type: project_type,
      params: section_params,
      projects_list: projects_list,
      page_projects: page_projects,
      page: page,
      total_pages: total_pages,
      stage_names: stage_names
    }
  end
```

with:

```ruby
  def build_section(project_type)
    section_submitted = params.dig(:sections, project_type.slug)
    section_params = section_submitted || {}

    projects = Project.where(project_type: project_type).includes(:project_type, project_stages: :stage_template).order(:name)
    projects = section_params[:status].present? ? projects.where(status: section_params[:status]) : projects.where.not(status: "archived")
    if section_params[:installer_id] == "none"
      projects = filter_by_no_installer(projects)
    elsif section_params[:installer_id].present?
      projects = filter_by_installer(projects, section_params[:installer_id])
    end
    projects = filter_by_date_range(projects, section_params[:from_date], section_params[:to_date])
    projects = filter_by_query(projects, section_params[:q])

    projects_list = projects.to_a
    per_page = 20
    page = [section_params[:page].to_i, 1].max
    total_pages = (projects_list.size / per_page.to_f).ceil
    page_projects = projects_list.drop((page - 1) * per_page).first(per_page)
    stage_names = StageTemplate.where(project_type: project_type).order(:name).pluck(:name)

    stage_name = if section_submitted.nil?
      project_type.stage_templates.find_by(default_in_filter: true)&.name
    else
      section_params[:stage_name]
    end

    {
      project_type: project_type,
      params: section_params,
      stage_name: stage_name,
      projects_list: projects_list,
      page_projects: page_projects,
      page: page,
      total_pages: total_pages,
      stage_names: stage_names
    }
  end
```

- [ ] **Step 4: Use the resolved `stage_name` in the view, and add the "Quitar filtros" link**

In `app/views/projects/_project_type_section.html.erb`, replace:

```erb
      <div class="col-auto">
        <%= form.label :stage_name, "Etapa", class: "form-label" %>
        <%= form.select :stage_name, section[:stage_names],
              { include_blank: "Todas", selected: section_params[:stage_name] }, class: "form-select" %>
      </div>
      <div class="col-auto">
        <%= form.label :q, "Buscar", class: "form-label" %>
        <%= form.text_field :q, value: section_params[:q], class: "form-control", placeholder: "Nombre, cliente, dirección..." %>
      </div>
      <div class="col-auto align-self-end">
        <%= form.submit "Filtrar", class: "btn btn-primary" %>
      </div>
    <% end %>
```

with:

```erb
      <div class="col-auto">
        <%= form.label :stage_name, "Etapa", class: "form-label" %>
        <%= form.select :stage_name, section[:stage_names],
              { include_blank: "Todas", selected: section[:stage_name] }, class: "form-select" %>
      </div>
      <div class="col-auto">
        <%= form.label :q, "Buscar", class: "form-label" %>
        <%= form.text_field :q, value: section_params[:q], class: "form-control", placeholder: "Nombre, cliente, dirección..." %>
      </div>
      <div class="col-auto align-self-end">
        <%= form.submit "Filtrar", class: "btn btn-primary" %>
        <%= link_to "Quitar filtros",
              projects_path(request.query_parameters.deep_merge(
                "sections" => { slug => { "status" => "", "installer_id" => "", "from_date" => "", "to_date" => "", "stage_name" => "", "q" => "", "page" => "" } }
              )),
              class: "btn btn-outline-secondary" %>
      </div>
    <% end %>
```

Then, further down in the same file, replace the `gantt_tasks` block's stage lookup:

```erb
  <%
    gantt_tasks = projects_list.filter_map do |project|
      if section_params[:stage_name].present?
        stage = project.project_stages.find { |s| s.name == section_params[:stage_name] }
        next if stage.nil?
```

with:

```erb
  <%
    gantt_tasks = projects_list.filter_map do |project|
      if section[:stage_name].present?
        stage = project.project_stages.find { |s| s.name == section[:stage_name] }
        next if stage.nil?
```

(the rest of that block — `stage_start`/`stage_end`/`else`/`first, last = project.gantt_window`/the hash literal — is unchanged).

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/projects_controller.rb app/views/projects/_project_type_section.html.erb test/controllers/projects_controller_test.rb
git commit -m "Apply the configured default stage on a fresh section load, add Quitar filtros button"
```

---

## Final Verification

- [ ] Run the full test suite: `bin/rails test`
- [ ] Expected: all tests pass, no regressions anywhere else in the app.
