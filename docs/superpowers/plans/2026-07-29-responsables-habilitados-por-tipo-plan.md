# Responsables habilitados por tipo de proyecto Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let an admin restrict which `ProjectType`s each `Responsible` can be assigned to (N:M), enforced with a hard model validation, configured via checkboxes on the responsible's own form, and reflected in every "who can I assign here" selector in the app.

**Architecture:** A new join model `ResponsibleProjectType` (`Responsible` ↔ `ProjectType`, no extra attributes). `ProjectResponsible` gains a validation rejecting assignments where the responsible isn't enabled for the project's type. A backfill migration enables every `Responsible` for every `ProjectType` it's already assigned to, so no existing assignment breaks. The admin form for `Responsible` gains checkboxes to manage this going forward, and the three "assign someone" selectors in the app (not the unrelated "filter the list by" selectors) narrow their options to only enabled responsibles.

**Tech Stack:** Rails 7.2, Minitest with fixtures.

## Global Constraints

- No new dependency.
- Only **assignment** selectors ("who can I assign to this project") are filtered by this — **filter** selectors (the existing "Responsable" dropdowns in `_project_type_section.html.erb`/`tracker.html.erb` that narrow the *displayed list of projects*) are untouched; they already scope to "who has an assignment of this type," a different concern.
- A hard validation means every existing test that creates a `ProjectResponsible` for a `Responsible` not already enabled for that project's type will start failing once Task 1 lands — Task 1 fixes every one of those (fixture-level for the two reused fixtures, explicit `ResponsibleProjectType.create!` calls for ad-hoc `Responsible.create!`s in tests).

---

### Task 1: `ResponsibleProjectType` model, hard validation, backfill, and fixing every test the new validation affects

**Files:**
- Create: `db/migrate/<timestamp>_create_responsible_project_types.rb`
- Create: `db/migrate/<timestamp>_backfill_responsible_project_types.rb`
- Create: `app/models/responsible_project_type.rb`
- Create: `test/models/responsible_project_type_test.rb`
- Create: `test/fixtures/responsible_project_types.yml`
- Modify: `app/models/responsible.rb`
- Modify: `app/models/project_type.rb`
- Modify: `app/models/project_responsible.rb`
- Modify: `test/models/project_responsible_test.rb`
- Modify: `test/controllers/projects_controller_test.rb`

**Interfaces:**
- Produces: `ResponsibleProjectType` (`belongs_to :responsible, :project_type`), `Responsible#project_types`/`#project_type_ids`, `ProjectType#responsibles`, `ProjectResponsible`'s new validation error on `:responsible`.

- [ ] **Step 1: Write the failing model tests**

```ruby
# test/models/responsible_project_type_test.rb
require "test_helper"

class ResponsibleProjectTypeTest < ActiveSupport::TestCase
  test "valid with a responsible and a project_type" do
    rpt = ResponsibleProjectType.new(responsible: responsibles(:ana_gomez), project_type: project_types(:instalaciones))
    assert rpt.valid?
  end

  test "invalid with a duplicate responsible/project_type pair" do
    ResponsibleProjectType.create!(responsible: responsibles(:ana_gomez), project_type: project_types(:instalaciones))
    dup = ResponsibleProjectType.new(responsible: responsibles(:ana_gomez), project_type: project_types(:instalaciones))
    assert_not dup.valid?
  end
end
```

Add to `test/models/project_responsible_test.rb` (inside `class ProjectResponsibleTest`, after `setup`):

```ruby
  test "invalid when the responsible is not enabled for the project's type" do
    ResponsibleProjectType.delete_all
    pr = ProjectResponsible.new(project: @project, responsible: @responsible, responsible_type: @responsible_type)
    assert_not pr.valid?
    assert_includes pr.errors[:responsible].join, "habilitado"
  end

  test "valid when the responsible is enabled for the project's type" do
    ResponsibleProjectType.create!(responsible: @responsible, project_type: @project_type)
    pr = ProjectResponsible.new(project: @project, responsible: @responsible, responsible_type: @responsible_type)
    assert pr.valid?
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/models/responsible_project_type_test.rb test/models/project_responsible_test.rb -n "/enabled|not enabled/"`
Expected: FAIL — `ResponsibleProjectType` doesn't exist yet; the two new `project_responsible_test.rb` tests fail because the validation doesn't exist yet either.

- [ ] **Step 3: Create the migration and model**

```ruby
# db/migrate/<timestamp>_create_responsible_project_types.rb
class CreateResponsibleProjectTypes < ActiveRecord::Migration[7.2]
  def change
    create_table :responsible_project_types do |t|
      t.references :responsible, null: false, foreign_key: true
      t.references :project_type, null: false, foreign_key: true
      t.timestamps
      t.index [:responsible_id, :project_type_id], unique: true, name: "index_responsible_project_types_on_pair"
    end
  end
end
```

Run: `bin/rails db:migrate`

```ruby
# app/models/responsible_project_type.rb
class ResponsibleProjectType < ApplicationRecord
  belongs_to :responsible
  belongs_to :project_type

  validates :responsible_id, uniqueness: { scope: :project_type_id }
end
```

- [ ] **Step 4: Wire up `Responsible` and `ProjectType`**

In `app/models/responsible.rb`, add next to `has_many :project_responsibles, dependent: :destroy`:

```ruby
  has_many :responsible_project_types, dependent: :destroy
  has_many :project_types, through: :responsible_project_types
```

In `app/models/project_type.rb`, add next to `has_many :responsible_types, dependent: :destroy`:

```ruby
  has_many :responsible_project_types, dependent: :destroy
  has_many :responsibles, through: :responsible_project_types
```

- [ ] **Step 5: Add the validation to `ProjectResponsible`**

In `app/models/project_responsible.rb`, add next to `validate :responsible_type_belongs_to_project_type`:

```ruby
  validate :responsible_enabled_for_project_type
```

Add this private method next to `responsible_type_belongs_to_project_type`:

```ruby
  def responsible_enabled_for_project_type
    return if responsible.nil? || project.nil?
    errors.add(:responsible, "no está habilitado para este tipo de proyecto") unless responsible.project_types.include?(project.project_type)
  end
```

- [ ] **Step 6: Add the fixture enabling the two existing `Responsible` fixtures for `instalaciones`**

```yaml
# test/fixtures/responsible_project_types.yml
ana_gomez_instalaciones:
  responsible_id: <%= ActiveRecord::FixtureSet.identify(:ana_gomez) %>
  project_type_id: <%= ActiveRecord::FixtureSet.identify(:instalaciones) %>
  created_at: <%= Time.current %>
  updated_at: <%= Time.current %>

pedro_responsable_instalaciones:
  responsible_id: <%= ActiveRecord::FixtureSet.identify(:pedro_responsable) %>
  project_type_id: <%= ActiveRecord::FixtureSet.identify(:instalaciones) %>
  created_at: <%= Time.current %>
  updated_at: <%= Time.current %>
```

- [ ] **Step 7: Fix the tests that create an ad-hoc `Responsible` and then a `ProjectResponsible` for it**

In `test/models/project_responsible_test.rb`, add this line to `setup` (right after `@responsible = Responsible.create!(name: "Ana Gómez")`):

```ruby
    ResponsibleProjectType.create!(responsible: @responsible, project_type: @project_type)
```

(This makes every pre-existing test in that file valid again — they all use `@responsible` against `@project_type`/`@project`, all `instalaciones`. The two new tests from Step 1 explicitly `ResponsibleProjectType.delete_all` or re-create the row to test both branches of the new validation in isolation.)

In `test/controllers/projects_controller_test.rb`, there are three separate tests that each do:

```ruby
    otro_responsable = Responsible.create!(name: "Otro")
```

followed shortly after by a `ProjectResponsible.create!(project: con_otro, responsible: otro_responsable, ...)` (or similar) for a project of `project_types(:instalaciones)`. Find all three (search for `Responsible.create!(name: "Otro")`) and add this line immediately after each, before the `ProjectResponsible.create!` that follows it:

```ruby
    ResponsibleProjectType.create!(responsible: otro_responsable, project_type: project_types(:instalaciones))
```

- [ ] **Step 8: Create the backfill migration**

```ruby
# db/migrate/<timestamp>_backfill_responsible_project_types.rb
class BackfillResponsibleProjectTypes < ActiveRecord::Migration[7.2]
  def up
    ProjectResponsible.includes(:responsible, project: :project_type).find_each do |pr|
      ResponsibleProjectType.find_or_create_by!(responsible_id: pr.responsible_id, project_type_id: pr.project.project_type_id)
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
```

Run: `bin/rails db:migrate`

- [ ] **Step 9: Run tests to verify they pass**

Run: `bin/rails test test/models/responsible_project_type_test.rb test/models/project_responsible_test.rb test/controllers/projects_controller_test.rb`
Expected: PASS

- [ ] **Step 10: Run the full suite**

Run: `bin/rails test`
Expected: PASS. If anything else fails, it's another test creating a `ProjectResponsible` for a not-yet-enabled `Responsible` that Step 7's search missed — grep the failure's test name, find its `Responsible`/`ProjectResponsible` setup, and add the same `ResponsibleProjectType.create!` pattern.

- [ ] **Step 11: Commit**

```bash
git add db/migrate db/schema.rb app/models/responsible_project_type.rb app/models/responsible.rb \
  app/models/project_type.rb app/models/project_responsible.rb test/models/responsible_project_type_test.rb \
  test/models/project_responsible_test.rb test/fixtures/responsible_project_types.yml \
  test/controllers/projects_controller_test.rb
git commit -m "Restrict ProjectResponsible to responsibles enabled for the project's type"
```

---

### Task 2: Admin form — enable/disable project types per responsible

**Files:**
- Modify: `app/controllers/admin/responsibles_controller.rb`
- Modify: `app/views/admin/responsibles/_form.html.erb`
- Modify: `test/controllers/admin/responsibles_controller_test.rb`

**Interfaces:**
- Consumes: `Responsible#project_type_ids` (Task 1, via the `has_many :project_types, through:` association's Rails-generated `_ids` method).

- [ ] **Step 1: Write the failing tests**

Add to `test/controllers/admin/responsibles_controller_test.rb`:

```ruby
  test "create with project_type_ids enables the responsible for those types" do
    other_type = ProjectType.create!(name: "Mantenimiento", slug: "mantenimiento")
    post admin_responsibles_path, params: {
      responsible: { name: "Nuevo", project_type_ids: [project_types(:instalaciones).id, other_type.id] }
    }
    created = Responsible.order(:id).last
    assert_equal [project_types(:instalaciones), other_type].sort_by(&:id), created.project_types.sort_by(&:id)
  end

  test "update can unenable every project type, leaving none" do
    responsible = responsibles(:ana_gomez)
    ResponsibleProjectType.create!(responsible: responsible, project_type: project_types(:instalaciones))

    patch admin_responsible_path(responsible), params: {
      responsible: { name: responsible.name, project_type_ids: [""] }
    }

    assert_equal [], responsible.reload.project_types
  end

  test "edit shows a checkbox per project type, checked for the ones already enabled" do
    ResponsibleProjectType.create!(responsible: responsibles(:ana_gomez), project_type: project_types(:instalaciones))
    get edit_admin_responsible_path(responsibles(:ana_gomez))
    assert_response :success
    assert_select "input[type=checkbox][name=?][checked=checked]", "responsible[project_type_ids][]", project_types(:instalaciones).id.to_s
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/controllers/admin/responsibles_controller_test.rb -n "/project_type_ids|checkbox per project type/"`
Expected: FAIL — `project_type_ids` isn't permitted yet, no checkboxes in the form yet.

- [ ] **Step 3: Permit the param**

In `app/controllers/admin/responsibles_controller.rb`, replace:

```ruby
  def responsible_params
    params.require(:responsible).permit(:name, :color, :user_id)
  end
```

with:

```ruby
  def responsible_params
    params.require(:responsible).permit(:name, :color, :user_id, project_type_ids: [])
  end
```

- [ ] **Step 4: Add the checkboxes to the form**

In `app/views/admin/responsibles/_form.html.erb`, add this block right before `<%= form.submit class: "btn btn-primary" %>`:

```erb
    <div class="mb-3">
      <%= form.label :project_type_ids, "Tipos de proyecto habilitados", class: "form-label d-block" %>
      <%= hidden_field_tag "responsible[project_type_ids][]", "" %>
      <% ProjectType.order(:name).each do |project_type| %>
        <div class="form-check">
          <%= check_box_tag "responsible[project_type_ids][]", project_type.id,
                responsible.project_type_ids.include?(project_type.id), class: "form-check-input", id: "project_type_ids_#{project_type.id}" %>
          <%= label_tag "project_type_ids_#{project_type.id}", project_type.name, class: "form-check-label" %>
        </div>
      <% end %>
    </div>
```

(The leading `hidden_field_tag` with an empty value guarantees `responsible[project_type_ids][]` is present in the submitted params even if every checkbox is unchecked — otherwise Rails would see no key at all and `Responsible#project_types=` would never be called, leaving stale enablements in place instead of clearing them. Rails' array-param parsing drops the blank `""` entry alongside any real ids, so this is safe with any combination of checked boxes.)

- [ ] **Step 5: Run tests to verify they pass**

Run: `bin/rails test test/controllers/admin/responsibles_controller_test.rb`
Expected: PASS

- [ ] **Step 6: Run the full suite**

Run: `bin/rails test`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add app/controllers/admin/responsibles_controller.rb app/views/admin/responsibles/_form.html.erb \
  test/controllers/admin/responsibles_controller_test.rb
git commit -m "Let an admin enable/disable project types per responsible"
```

---

### Task 3: Filter the assignment selectors to only enabled responsibles

**Files:**
- Modify: `app/views/admin/project_types/show.html.erb`
- Modify: `app/views/projects/show.html.erb`
- Modify: `app/views/projects/_project_type_section.html.erb`
- Modify: `test/controllers/admin/project_types_controller_test.rb`
- Modify: `test/controllers/projects_controller_test.rb`
- Modify: `test/controllers/project_responsibles_controller_test.rb`

**Interfaces:**
- Consumes: `ProjectType#responsibles` (Task 1).

- [ ] **Step 1: Write the failing tests**

In `test/controllers/admin/project_types_controller_test.rb`, replace the existing test `"show lists the Responsible catalog with a link to manage it"` (added in a prior plan) with:

```ruby
  test "show lists only the Responsible catalog entries enabled for this project type" do
    enabled = Responsible.create!(name: "Ana Gómez", color: "#ff0000")
    ResponsibleProjectType.create!(responsible: enabled, project_type: project_types(:instalaciones))
    other_type = ProjectType.create!(name: "Mantenimiento", slug: "mantenimiento")
    not_enabled = Responsible.create!(name: "No Habilitado")
    ResponsibleProjectType.create!(responsible: not_enabled, project_type: other_type)

    get admin_project_type_path(project_types(:instalaciones))
    assert_response :success
    assert_select ".card-header", "Responsables"
    assert_select "body", /Ana Gómez/
    assert_select "body", text: /No Habilitado/, count: 0
    assert_select "a[href=?]", admin_responsibles_path, text: "Administrar responsables"
  end
```

In `test/controllers/projects_controller_test.rb`, add a new test (find the tests around the "Responsables" card added in a prior plan and add this alongside):

```ruby
  test "show's Responsables assignment form only offers responsibles enabled for this project's type" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    other_type = ProjectType.create!(name: "Mantenimiento", slug: "mantenimiento")
    not_enabled = Responsible.create!(name: "No Habilitado")
    ResponsibleProjectType.create!(responsible: not_enabled, project_type: other_type)

    get project_path(project)
    assert_response :success
    assert_select "select[name=?] option", "project_responsible[responsible_id]", text: "Ana Gómez"
    assert_select "select[name=?] option", "project_responsible[responsible_id]", text: "No Habilitado", count: 0
  end
```

In `test/controllers/projects_controller_test.rb`, add a test for the bulk-assign dropdown too:

```ruby
  test "index's bulk-assign selector only offers responsibles enabled for this project type" do
    other_type = ProjectType.create!(name: "Mantenimiento", slug: "mantenimiento")
    not_enabled = Responsible.create!(name: "No Habilitado")
    ResponsibleProjectType.create!(responsible: not_enabled, project_type: other_type)

    get project_type_projects_path(project_types(:instalaciones).slug)
    assert_response :success
    assert_select "select#bulk-assign-responsible-select-#{project_types(:instalaciones).slug} option", text: "Ana Gómez"
    assert_select "select#bulk-assign-responsible-select-#{project_types(:instalaciones).slug} option", text: "No Habilitado", count: 0
  end
```

(These three new tests rely on `responsibles(:ana_gomez)` already being enabled for `instalaciones` via the fixture added in Task 1 — no extra setup needed for the "enabled" side.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/controllers/admin/project_types_controller_test.rb test/controllers/projects_controller_test.rb -n "/only offers responsibles enabled|only lists only the Responsible catalog/"`
Expected: FAIL — all three selectors currently list every `Responsible`, including ones not enabled for this type.

- [ ] **Step 3: Filter `admin/project_types/show.html.erb`**

Replace:

```erb
      <% Responsible.order(:name).each do |responsible| %>
```

with:

```erb
      <% @project_type.responsibles.order(:name).each do |responsible| %>
```

- [ ] **Step 4: Filter the assignment form in `projects/show.html.erb`**

Replace:

```erb
            <%= form.collection_select :responsible_id, Responsible.order(:name), :id, :name, { include_blank: "Responsable" }, class: "form-select" %>
```

with:

```erb
            <%= form.collection_select :responsible_id, @project.project_type.responsibles.order(:name), :id, :name, { include_blank: "Responsable" }, class: "form-select" %>
```

- [ ] **Step 5: Filter the bulk-assign dropdown in `_project_type_section.html.erb`**

Replace:

```erb
        <%= f.select :responsible_id, Responsible.order(:name).collect { |r| [r.name, r.id] },
              { include_blank: "Elegí un responsable" }, class: "form-select", id: "bulk-assign-responsible-select-#{slug}" %>
```

with:

```erb
        <%= f.select :responsible_id, project_type.responsibles.order(:name).collect { |r| [r.name, r.id] },
              { include_blank: "Elegí un responsable" }, class: "form-select", id: "bulk-assign-responsible-select-#{slug}" %>
```

- [ ] **Step 6: Check for now-invalid existing tests**

The bulk-assign test `"bulk_assign_responsible replaces an existing project-wide assignment of the same type"` and similar ones in `test/controllers/projects_controller_test.rb` create an `otro_responsable`/select it by id directly via `patch` params — those still work fine since submitting a `responsible_id` by id doesn't depend on it appearing in the rendered `<select>` options (Task 1's Step 7 already ensured every ad-hoc responsible used in an actual `ProjectResponsible` is enabled). Re-run the full suite in the next step to confirm nothing else broke.

- [ ] **Step 7: Run tests to verify they pass**

Run: `bin/rails test test/controllers/admin/project_types_controller_test.rb test/controllers/projects_controller_test.rb test/controllers/project_responsibles_controller_test.rb`
Expected: PASS

- [ ] **Step 8: Run the full suite**

Run: `bin/rails test`
Expected: PASS

- [ ] **Step 9: Commit**

```bash
git add app/views/admin/project_types/show.html.erb app/views/projects/show.html.erb \
  app/views/projects/_project_type_section.html.erb test/controllers/admin/project_types_controller_test.rb \
  test/controllers/projects_controller_test.rb test/controllers/project_responsibles_controller_test.rb
git commit -m "Filter responsible-assignment selectors to only those enabled for the project's type"
```
