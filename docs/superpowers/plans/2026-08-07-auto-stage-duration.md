# Duración Automática de Etapas Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a Tipo de Proyecto configure automatic stage-date calculation: on manual project creation (with a provided start date) or later via a "pending" panel action (for imported projects), stage dates get computed in sequence from `DurationProfile` rules matched against a numeric custom field's value.

**Architecture:** A new `DurationProfile` model (belongs to `ProjectType`, admin-managed like `StageTemplate`) stores comparison rules + a `durations` jsonb map of `stage_template_id → days`. `ProjectType` gains an enable flag and a reference `FieldDefinition`. `Project` gains the matching/calculation logic, invoked either at creation (via a virtual attribute carrying the user-provided start date) or via a new controller action for projects that didn't get one (imports).

**Tech Stack:** Rails 7.2 (ERB, ActiveRecord), Stimulus (reused `drag-reorder` controller), Minitest, PostgreSQL (jsonb).

## Global Constraints

- 100% configurable per Tipo de Proyecto, off by default (`auto_stage_duration_enabled: false`) — zero behavior change for types that don't enable it.
- No new dependencies. Reuse the existing `drag-reorder` Stimulus controller (`app/javascript/controllers/drag_reorder_controller.js`) for `DurationProfile` ordering — do not write new JS.
- Rule priority is `position` ascending (same drag-to-reorder pattern as `stage_templates`/`field_definitions`) — first matching profile wins.
- Operators: `greater_than`, `less_than`, `between`, `equal_to` — exact string values, used both in the DB and in Ruby `case` statements throughout.
- Duration = calendar days inclusive of the start date: `end_date = start_date + (days - 1)`; the next stage's cursor is `end_date + 1.day`.
- If no profile matches, no reference field is configured, or no start date was provided: stages are created without dates — identical to today's `build_stages_from_template` behavior. Never raise, never block project creation.
- Excel import (`app/controllers/imports_controller.rb`) is not modified — it never provides a start date, so imported projects always land in the "no date" case, then get completed via the pending panel.
- The "Pendientes de fecha" panel and its underlying query already exist (`app/views/projects/_project_type_section.html.erb`, `Project#stages_missing_dates`) — extend it, do not duplicate it.

---

### Task 1: `DurationProfile` model, migration, and `ProjectType` auto-duration columns

**Files:**
- Create: `db/migrate/<timestamp>_create_duration_profiles_and_add_auto_stage_duration_to_project_types.rb`
- Create: `app/models/duration_profile.rb`
- Modify: `app/models/project_type.rb`
- Test: `test/models/duration_profile_test.rb`

**Interfaces:**
- Produces: `DurationProfile` — `belongs_to :project_type`, columns `operator:string`, `min_value:decimal`, `max_value:decimal`, `position:integer`, `durations:jsonb`. Instance method `matches?(value) → true/false` (`value` is a `Float`). `DurationProfile::OPERATORS` (`Array<String>`, the 4 values). `ProjectType#duration_profiles` (ordered by `:position`), `ProjectType#duration_reference_field_definition` (belongs_to, optional), `ProjectType#auto_stage_duration_enabled?`. Tasks 2-6 all consume these names as given here — do not rename.

- [ ] **Step 1: Write the failing model tests**

Create `test/models/duration_profile_test.rb`:

```ruby
require "test_helper"

class DurationProfileTest < ActiveSupport::TestCase
  setup { @project_type = project_types(:instalaciones) }

  test "valid with greater_than and min_value" do
    profile = DurationProfile.new(project_type: @project_type, operator: "greater_than", min_value: 100)
    assert profile.valid?, profile.errors.full_messages.to_s
  end

  test "invalid operator" do
    profile = DurationProfile.new(project_type: @project_type, operator: "weird", min_value: 100)
    assert_not profile.valid?
  end

  test "greater_than requires min_value" do
    profile = DurationProfile.new(project_type: @project_type, operator: "greater_than")
    assert_not profile.valid?
    assert_includes profile.errors[:min_value], "es obligatorio para este operador"
  end

  test "less_than requires max_value" do
    profile = DurationProfile.new(project_type: @project_type, operator: "less_than")
    assert_not profile.valid?
    assert_includes profile.errors[:max_value], "es obligatorio para este operador"
  end

  test "between requires both min_value and max_value, and min <= max" do
    profile = DurationProfile.new(project_type: @project_type, operator: "between", min_value: 500, max_value: 100)
    assert_not profile.valid?
    assert_includes profile.errors[:max_value], "debe ser mayor o igual al valor mínimo"
  end

  test "equal_to requires min_value" do
    profile = DurationProfile.new(project_type: @project_type, operator: "equal_to")
    assert_not profile.valid?
    assert_includes profile.errors[:min_value], "es obligatorio para este operador"
  end

  test "durations must reference stage_templates belonging to the same project_type" do
    other_type = ProjectType.create!(name: "Otro", slug: "otro")
    foreign_stage = StageTemplate.create!(project_type: other_type, name: "Ajena")
    profile = DurationProfile.new(
      project_type: @project_type, operator: "greater_than", min_value: 1,
      durations: { foreign_stage.id.to_s => 5 }
    )
    assert_not profile.valid?
    assert_includes profile.errors[:durations], "hace referencia a un subproceso inválido"
  end

  test "durations values must be positive integers" do
    stage = stage_templates(:entrega)
    profile = DurationProfile.new(
      project_type: @project_type, operator: "greater_than", min_value: 1,
      durations: { stage.id.to_s => -3 }
    )
    assert_not profile.valid?
    assert_includes profile.errors[:durations], "debe ser un número de días positivo"
  end

  test "matches? for greater_than" do
    profile = DurationProfile.new(operator: "greater_than", min_value: 100)
    assert profile.matches?(150)
    assert_not profile.matches?(100)
    assert_not profile.matches?(50)
  end

  test "matches? for less_than" do
    profile = DurationProfile.new(operator: "less_than", max_value: 100)
    assert profile.matches?(50)
    assert_not profile.matches?(100)
    assert_not profile.matches?(150)
  end

  test "matches? for between" do
    profile = DurationProfile.new(operator: "between", min_value: 100, max_value: 500)
    assert profile.matches?(100)
    assert profile.matches?(500)
    assert profile.matches?(300)
    assert_not profile.matches?(99)
    assert_not profile.matches?(501)
  end

  test "matches? for equal_to" do
    profile = DurationProfile.new(operator: "equal_to", min_value: 42)
    assert profile.matches?(42)
    assert_not profile.matches?(43)
  end

  test "project_type has_many duration_profiles ordered by position" do
    second = DurationProfile.create!(project_type: @project_type, operator: "greater_than", min_value: 1, position: 1)
    first = DurationProfile.create!(project_type: @project_type, operator: "less_than", max_value: 1, position: 0)
    assert_equal [first, second], @project_type.duration_profiles.to_a
  end
end
```

- [ ] **Step 2: Run to confirm it fails**

Run: `bin/rails test test/models/duration_profile_test.rb`
Expected: FAIL — `NameError: uninitialized constant DurationProfile` (the model, table, and `ProjectType` associations don't exist yet).

- [ ] **Step 3: Generate and write the migration**

Run: `bin/rails generate migration CreateDurationProfilesAndAddAutoStageDurationToProjectTypes` (note the exact generated filename it prints).

Replace its contents with:

```ruby
class CreateDurationProfilesAndAddAutoStageDurationToProjectTypes < ActiveRecord::Migration[7.2]
  def change
    add_column :project_types, :auto_stage_duration_enabled, :boolean, default: false, null: false
    add_reference :project_types, :duration_reference_field_definition, foreign_key: { to_table: :field_definitions }, null: true

    create_table :duration_profiles do |t|
      t.references :project_type, null: false, foreign_key: true
      t.string :operator, null: false
      t.decimal :min_value
      t.decimal :max_value
      t.integer :position, default: 0, null: false
      t.jsonb :durations, default: {}, null: false
      t.timestamps
    end
  end
end
```

- [ ] **Step 4: Run the migration**

Run: `bin/rails db:migrate`
Expected: migration runs; `db/schema.rb` gains the two new `project_types` columns and the `duration_profiles` table.

- [ ] **Step 5: Create the `DurationProfile` model**

Create `app/models/duration_profile.rb`:

```ruby
class DurationProfile < ApplicationRecord
  OPERATORS = %w[greater_than less_than between equal_to].freeze

  belongs_to :project_type

  validates :operator, inclusion: { in: OPERATORS }
  validate :values_present_for_operator
  validate :durations_reference_valid_stage_templates

  def matches?(value)
    case operator
    when "greater_than" then min_value.present? && value > min_value
    when "less_than" then max_value.present? && value < max_value
    when "between" then min_value.present? && max_value.present? && value.between?(min_value, max_value)
    when "equal_to" then min_value.present? && value == min_value
    else false
    end
  end

  private

  def values_present_for_operator
    case operator
    when "greater_than", "equal_to"
      errors.add(:min_value, "es obligatorio para este operador") if min_value.blank?
    when "less_than"
      errors.add(:max_value, "es obligatorio para este operador") if max_value.blank?
    when "between"
      errors.add(:min_value, "es obligatorio para este operador") if min_value.blank?
      errors.add(:max_value, "es obligatorio para este operador") if max_value.blank?
      if min_value.present? && max_value.present? && min_value > max_value
        errors.add(:max_value, "debe ser mayor o igual al valor mínimo")
      end
    end
  end

  def durations_reference_valid_stage_templates
    return if durations.blank?
    valid_ids = project_type.stage_templates.pluck(:id).map(&:to_s)
    durations.each do |stage_template_id, days|
      unless valid_ids.include?(stage_template_id.to_s)
        errors.add(:durations, "hace referencia a un subproceso inválido")
        next
      end
      unless days.to_s.match?(/\A\d+\z/) && days.to_i.positive?
        errors.add(:durations, "debe ser un número de días positivo")
      end
    end
  end
end
```

- [ ] **Step 6: Add the associations to `ProjectType`**

In `app/models/project_type.rb`, add two lines after the existing `has_many :stage_templates` (line 3):

```ruby
  has_many :duration_profiles, -> { order(:position) }, dependent: :destroy
  belongs_to :duration_reference_field_definition, class_name: "FieldDefinition", optional: true
```

- [ ] **Step 7: Run the tests to confirm they pass**

Run: `bin/rails test test/models/duration_profile_test.rb`
Expected: all PASS

- [ ] **Step 8: Run the full model test suite**

Run: `bin/rails test test/models/`
Expected: all PASS, 0 failures.

- [ ] **Step 9: Commit**

```bash
git add db/migrate db/schema.rb app/models/duration_profile.rb app/models/project_type.rb test/models/duration_profile_test.rb
git commit -m "Agregar modelo DurationProfile y columnas de duración automática en ProjectType"
```

---

### Task 2: Admin settings card — enable flag + reference field selector

**Files:**
- Modify: `app/controllers/admin/project_types_controller.rb`
- Modify: `app/views/admin/project_types/show.html.erb`
- Test: `test/controllers/admin/project_types_controller_test.rb`

**Interfaces:**
- Consumes: `ProjectType#auto_stage_duration_enabled`, `#duration_reference_field_definition_id` (Task 1).
- Produces: `Admin::ProjectTypesController#update` now persists these two fields (submitted from a new form on the `show` page, reusing the existing `update` action/route — no new controller action).

- [ ] **Step 1: Write the failing tests**

Add to `test/controllers/admin/project_types_controller_test.rb`, inside the class:

```ruby
  test "show displays the Cálculo automático de duración card" do
    get admin_project_type_path(project_types(:instalaciones))
    assert_response :success
    assert_select ".card-header", "Cálculo automático de duración"
  end

  test "show's auto-duration form only lists numeric field definitions as reference options" do
    project_type = project_types(:instalaciones)
    FieldDefinition.create!(project_type: project_type, key: "cantidad", label: "Cantidad de Unidades", data_type: "number", position: 10)
    FieldDefinition.create!(project_type: project_type, key: "notas", label: "Notas", data_type: "textarea", position: 11)

    get admin_project_type_path(project_type)
    assert_response :success
    assert_select "select[name=?] option", "project_type[duration_reference_field_definition_id]", text: "Cantidad de Unidades"
    assert_select "select[name=?] option", "project_type[duration_reference_field_definition_id]", text: "Notas", count: 0
  end

  test "update persists auto_stage_duration_enabled and duration_reference_field_definition_id" do
    project_type = project_types(:instalaciones)
    field = FieldDefinition.create!(project_type: project_type, key: "cantidad", label: "Cantidad", data_type: "number", position: 10)

    patch admin_project_type_path(project_type), params: {
      project_type: { name: project_type.name, slug: project_type.slug, auto_stage_duration_enabled: "1", duration_reference_field_definition_id: field.id }
    }

    assert_redirected_to admin_project_type_path(project_type)
    project_type.reload
    assert_equal true, project_type.auto_stage_duration_enabled
    assert_equal field.id, project_type.duration_reference_field_definition_id
  end
```

- [ ] **Step 2: Run to confirm they fail**

Run: `bin/rails test test/controllers/admin/project_types_controller_test.rb -n test_show_displays_the_C_lculo_autom_tico_de_duraci_n_card -n "test_show_s_auto_duration_form_only_lists_numeric_field_definitions_as_reference_options" -n test_update_persists_auto_stage_duration_enabled_and_duration_reference_field_definition_id`
Expected: all FAIL — no such card exists, and the params aren't permitted yet.

- [ ] **Step 3: Permit the new params**

In `app/controllers/admin/project_types_controller.rb`, update `project_type_params` (currently `permit(:name, :slug, :require_stage_dates)`):

```ruby
  def project_type_params
    params.require(:project_type).permit(:name, :slug, :require_stage_dates, :auto_stage_duration_enabled, :duration_reference_field_definition_id)
  end
```

- [ ] **Step 4: Add the card to the show page**

In `app/views/admin/project_types/show.html.erb`, insert this block right after the closing `</div>` of the "Subprocesos" card (right before the "Tipos de Bitácora" card):

```erb
<div class="card mb-4">
  <div class="card-header">Cálculo automático de duración</div>
  <div class="card-body">
    <%= form_with model: [:admin, @project_type], method: :patch do |form| %>
      <div class="mb-3 form-check">
        <%= form.check_box :auto_stage_duration_enabled, class: "form-check-input" %>
        <%= form.label :auto_stage_duration_enabled, "Calcular duración automáticamente", class: "form-check-label" %>
      </div>
      <div class="mb-3">
        <%= form.label :duration_reference_field_definition_id, "Campo numérico de referencia", class: "form-label" %>
        <%= form.collection_select :duration_reference_field_definition_id,
              @project_type.field_definitions.where(data_type: %w[number currency percent]),
              :id, :label, { include_blank: "Ninguno" }, class: "form-select" %>
      </div>
      <%= form.submit "Guardar", class: "btn btn-primary btn-sm" %>
    <% end %>
  </div>
</div>
```

- [ ] **Step 5: Run the tests to confirm they pass**

Run: `bin/rails test test/controllers/admin/project_types_controller_test.rb -n test_show_displays_the_C_lculo_autom_tico_de_duraci_n_card -n "test_show_s_auto_duration_form_only_lists_numeric_field_definitions_as_reference_options" -n test_update_persists_auto_stage_duration_enabled_and_duration_reference_field_definition_id`
Expected: all PASS

- [ ] **Step 6: Run the full admin project types test file**

Run: `bin/rails test test/controllers/admin/project_types_controller_test.rb`
Expected: all PASS, 0 failures — the pre-existing `"create with blank name re-renders form with error"` test and others must still pass unmodified.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/admin/project_types_controller.rb app/views/admin/project_types/show.html.erb test/controllers/admin/project_types_controller_test.rb
git commit -m "Agregar tarjeta de configuración de duración automática en el admin de Tipo de Proyecto"
```

---

### Task 3: Admin CRUD for `DurationProfile`

**Files:**
- Create: `app/controllers/admin/duration_profiles_controller.rb`
- Create: `app/views/admin/duration_profiles/_form.html.erb`
- Create: `app/views/admin/duration_profiles/new.html.erb`
- Create: `app/views/admin/duration_profiles/edit.html.erb`
- Modify: `config/routes.rb`
- Modify: `app/views/admin/project_types/show.html.erb`
- Modify: `config/locales/es.yml`
- Test: `test/controllers/admin/duration_profiles_controller_test.rb`

**Interfaces:**
- Consumes: `DurationProfile` (Task 1), `ProjectType#duration_profiles` (Task 1), the reusable `drag-reorder` Stimulus controller (already in the codebase, no changes needed — same `data-controller="drag-reorder"` / `data-drag-reorder-url-value` / `<li data-id>` / `.drag-handle` pattern already used for `stage-templates-list`).
- Produces: routes `admin_project_type_duration_profiles_path`, `admin_project_type_duration_profile_path`, `new_admin_project_type_duration_profile_path`, `edit_admin_project_type_duration_profile_path`, `reorder_admin_project_type_duration_profiles_path`. No later task depends on these route names directly (Task 6 uses `apply_auto_duration_project_path`, a different resource).

- [ ] **Step 1: Add the routes**

In `config/routes.rb`, inside the `resources :project_types do ... end` block, right after the `resources :stage_templates` block (after its closing `end` on line 15):

```ruby
      resources :duration_profiles, except: [:index, :show] do
        patch :reorder, on: :collection
      end
```

- [ ] **Step 2: Write the failing controller tests**

Create `test/controllers/admin/duration_profiles_controller_test.rb`:

```ruby
require "test_helper"

class Admin::DurationProfilesControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:juan) }
  setup { @project_type = project_types(:instalaciones) }

  test "create adds a duration profile with per-stage durations" do
    entrega = stage_templates(:entrega)
    assert_difference("@project_type.duration_profiles.count", 1) do
      post admin_project_type_duration_profiles_path(@project_type), params: {
        duration_profile: { operator: "greater_than", min_value: 100, durations: { entrega.id.to_s => "5" } }
      }
    end
    assert_redirected_to admin_project_type_path(@project_type)
    assert_equal 5, @project_type.duration_profiles.last.durations[entrega.id.to_s].to_i
  end

  test "create with invalid operator re-renders form with error" do
    assert_no_difference("@project_type.duration_profiles.count") do
      post admin_project_type_duration_profiles_path(@project_type), params: {
        duration_profile: { operator: "weird" }
      }
    end
    assert_response :unprocessable_entity
  end

  test "update saves changed values" do
    profile = DurationProfile.create!(project_type: @project_type, operator: "greater_than", min_value: 100)
    patch admin_project_type_duration_profile_path(@project_type, profile), params: {
      duration_profile: { operator: "greater_than", min_value: 200 }
    }
    assert_redirected_to admin_project_type_path(@project_type)
    assert_equal 200, profile.reload.min_value.to_i
  end

  test "destroy removes a duration profile" do
    profile = DurationProfile.create!(project_type: @project_type, operator: "greater_than", min_value: 100)
    assert_difference("@project_type.duration_profiles.count", -1) do
      delete admin_project_type_duration_profile_path(@project_type, profile)
    end
  end

  test "reorder updates position according to the submitted id order" do
    first = DurationProfile.create!(project_type: @project_type, operator: "greater_than", min_value: 1, position: 0)
    second = DurationProfile.create!(project_type: @project_type, operator: "less_than", max_value: 1, position: 1)

    patch reorder_admin_project_type_duration_profiles_path(@project_type), params: { ids: [second.id, first.id] }, as: :json
    assert_response :success

    assert_equal 0, second.reload.position
    assert_equal 1, first.reload.position
  end

  test "new form renders one duration input per stage template" do
    get new_admin_project_type_duration_profile_path(@project_type)
    assert_response :success
    @project_type.stage_templates.each do |stage|
      assert_select "input[name=?]", "duration_profile[durations][#{stage.id}]"
    end
  end

  test "new and edit show the submit button in Spanish" do
    get new_admin_project_type_duration_profile_path(@project_type)
    assert_response :success
    assert_select "input[value=?]", "Crear Perfil de duración"

    profile = DurationProfile.create!(project_type: @project_type, operator: "greater_than", min_value: 100)
    get edit_admin_project_type_duration_profile_path(@project_type, profile)
    assert_response :success
    assert_select "input[value=?]", "Actualizar Perfil de duración"
  end
end
```

**Note on Spanish labels:** `config/locales/es.yml` has an `activerecord.models`/`activerecord.attributes` section (see `stage_template: "Subproceso"` around line 38) that every existing admin CRUD resource relies on for its "Crear X"/"Actualizar X" submit button text and field labels. `DurationProfile` needs an entry there too, or its submit button falls back to the literal (English-ish) class-derived string "Duration profile" instead of Spanish — added in Step 5 below.

- [ ] **Step 3: Run to confirm they fail**

Run: `bin/rails test test/controllers/admin/duration_profiles_controller_test.rb`
Expected: FAIL — `Admin::DurationProfilesController` doesn't exist yet, `uninitialized constant` or routing error.

- [ ] **Step 4: Create the controller**

Create `app/controllers/admin/duration_profiles_controller.rb`:

```ruby
class Admin::DurationProfilesController < Admin::BaseController
  before_action :set_project_type
  before_action :set_duration_profile, only: [:edit, :update, :destroy]

  def new
    @duration_profile = @project_type.duration_profiles.new
  end

  def create
    @duration_profile = @project_type.duration_profiles.new(duration_profile_params)
    if @duration_profile.save
      redirect_to admin_project_type_path(@project_type)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @duration_profile.update(duration_profile_params)
      redirect_to admin_project_type_path(@project_type)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @duration_profile.destroy
    redirect_to admin_project_type_path(@project_type)
  end

  def reorder
    Array(params[:ids]).each_with_index do |id, index|
      @project_type.duration_profiles.where(id: id).update_all(position: index)
    end
    head :ok
  end

  private

  def set_project_type
    @project_type = ProjectType.find(params[:project_type_id])
  end

  def set_duration_profile
    @duration_profile = @project_type.duration_profiles.find(params[:id])
  end

  def duration_profile_params
    params.require(:duration_profile).permit(:operator, :min_value, :max_value, :position, durations: {})
  end
end
```

- [ ] **Step 5: Add Spanish model/attribute labels**

In `config/locales/es.yml`, add `duration_profile: "Perfil de duración"` to the `activerecord.models` block (right after the existing `stage_template: "Subproceso"` line):

```yaml
      stage_template: "Subproceso"
      duration_profile: "Perfil de duración"
```

And add a new block under `activerecord.attributes` (right after the existing `stage_template:` attributes block, which ends after its `position: "Posición"` line):

```yaml
      duration_profile:
        min_value: "Valor mínimo"
        max_value: "Valor máximo"
        position: "Posición"
        durations: "Duraciones"
```

(`:operator` is intentionally omitted — its form label passes explicit text `"Comparación"` in Step 6 below, so it doesn't need a translation entry.)

- [ ] **Step 6: Create the form partial**

Create `app/views/admin/duration_profiles/_form.html.erb`:

```erb
<%= panel_card("#{duration_profile.persisted? ? 'Editar' : 'Nuevo'} perfil de duración — #{project_type.name}") do %>
  <%= form_with model: [:admin, project_type, duration_profile] do |form| %>
    <% if duration_profile.errors.any? %>
      <div class="alert alert-danger">
        <ul class="mb-0">
          <% duration_profile.errors.full_messages.each do |message| %>
            <li><%= message %></li>
          <% end %>
        </ul>
      </div>
    <% end %>

    <div class="mb-3">
      <%= form.label :operator, "Comparación", class: "form-label" %>
      <%= form.select :operator,
            [["Mayor que", "greater_than"], ["Menor que", "less_than"], ["Entre", "between"], ["Igual a", "equal_to"]],
            { include_blank: false }, class: "form-select" %>
    </div>
    <div class="mb-3">
      <%= form.label :min_value, "Valor mínimo (o exacto, para \"Igual a\")", class: "form-label" %>
      <%= form.number_field :min_value, step: "any", class: "form-control" %>
    </div>
    <div class="mb-3">
      <%= form.label :max_value, "Valor máximo", class: "form-label" %>
      <%= form.number_field :max_value, step: "any", class: "form-control" %>
    </div>
    <div class="mb-3">
      <%= form.label :position, class: "form-label" %>
      <%= form.number_field :position, class: "form-control" %>
    </div>

    <h6>Duración por etapa (días)</h6>
    <% project_type.stage_templates.each do |stage| %>
      <div class="mb-2">
        <%= label_tag "duration_profile_durations_#{stage.id}", stage.name, class: "form-label" %>
        <%= number_field_tag "duration_profile[durations][#{stage.id}]", duration_profile.durations[stage.id.to_s], min: 1, class: "form-control" %>
      </div>
    <% end %>

    <%= form.submit class: "btn btn-primary" %>
  <% end %>
<% end %>
```

- [ ] **Step 7: Create `new.html.erb` and `edit.html.erb`**

Create `app/views/admin/duration_profiles/new.html.erb`:

```erb
<%= render "form", project_type: @project_type, duration_profile: @duration_profile %>
```

Create `app/views/admin/duration_profiles/edit.html.erb`:

```erb
<%= render "form", project_type: @project_type, duration_profile: @duration_profile %>
```

- [ ] **Step 8: Add the drag-reorder list to the show page**

In `app/views/admin/project_types/show.html.erb`, inside the "Cálculo automático de duración" card added in Task 2, right before its closing `</div></div>` (after the `form.submit` line), add:

```erb
    <hr>
    <%= link_to "Nuevo perfil", new_admin_project_type_duration_profile_path(@project_type), class: "btn btn-primary btn-sm mb-2" %>
    <ol class="list-group list-group-numbered list-group-flush" id="duration-profiles-list" data-controller="drag-reorder"
        data-drag-reorder-url-value="<%= reorder_admin_project_type_duration_profiles_path(@project_type) %>"
        data-action="dragstart->drag-reorder#start dragend->drag-reorder#end dragover->drag-reorder#over drop->drag-reorder#drop">
      <% @project_type.duration_profiles.each do |profile| %>
        <li class="list-group-item d-flex justify-content-between align-items-center" data-id="<%= profile.id %>">
          <span>
            <span class="drag-handle me-2" draggable="true" style="cursor: grab;">⠿</span>
            <%= profile.operator %> <%= profile.min_value %><%= " - #{profile.max_value}" if profile.operator == "between" %>
          </span>
          <span>
            <%= link_to "Editar", edit_admin_project_type_duration_profile_path(@project_type, profile), class: "btn btn-outline-secondary btn-sm" %>
            <%= button_to "Eliminar", admin_project_type_duration_profile_path(@project_type, profile), method: :delete,
                  class: "btn btn-outline-danger btn-sm", form: { style: "display:inline-block", onsubmit: "return confirm('¿Eliminar perfil?')" } %>
          </span>
        </li>
      <% end %>
    </ol>
```

- [ ] **Step 9: Run the tests to confirm they pass**

Run: `bin/rails test test/controllers/admin/duration_profiles_controller_test.rb`
Expected: all PASS

- [ ] **Step 10: Run the full admin test suite**

Run: `bin/rails test test/controllers/admin/`
Expected: all PASS, 0 failures.

- [ ] **Step 11: Commit**

```bash
git add config/routes.rb config/locales/es.yml app/controllers/admin/duration_profiles_controller.rb app/views/admin/duration_profiles app/views/admin/project_types/show.html.erb test/controllers/admin/duration_profiles_controller_test.rb
git commit -m "Agregar CRUD de admin para DurationProfile"
```

---

### Task 4: Calculation logic on `Project`

**Files:**
- Modify: `app/models/project.rb`
- Test: `test/models/project_test.rb`

**Interfaces:**
- Consumes: `ProjectType#auto_stage_duration_enabled?`, `#duration_reference_field_definition`, `#duration_profiles` (Task 1), `DurationProfile#matches?` (Task 1).
- Produces: `Project#auto_duration_start_date` (virtual `attr_accessor`, String or Date), `Project#matching_duration_profile → DurationProfile | nil`, `Project#apply_auto_duration!(start_date) → true | false` (start_date: String or Date; mutates `project_stages`, returns whether it actually applied anything), `Project#pending_auto_duration_start_date? → true | false`. Task 5 sets `auto_duration_start_date` before save; `build_stages_from_template` calls `apply_auto_duration!`. Task 6 calls `apply_auto_duration!` directly and `pending_auto_duration_start_date?` for the panel.

- [ ] **Step 1: Write the failing tests**

Add to `test/models/project_test.rb`, inside the `ProjectTest` class (it already has a `setup { @project_type = project_types(:instalaciones) }` block — reuse it):

```ruby
  test "apply_auto_duration! sets sequential dates per stage_template when a profile matches" do
    field = FieldDefinition.create!(project_type: @project_type, key: "cantidad", label: "Cantidad", data_type: "number", position: 10)
    @project_type.update!(auto_stage_duration_enabled: true, duration_reference_field_definition: field)
    diseno = stage_templates(:diseno_aprobacion)
    revision = stage_templates(:revision_inicial)
    DurationProfile.create!(
      project_type: @project_type, operator: "between", min_value: 100, max_value: 500,
      durations: { diseno.id.to_s => 5, revision.id.to_s => 3 }
    )
    project = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: { "cantidad" => "300" })

    assert project.apply_auto_duration!(Date.new(2026, 1, 1))

    diseno_stage = project.project_stages.find_by(stage_template: diseno)
    revision_stage = project.project_stages.find_by(stage_template: revision)
    assert_equal Date.new(2026, 1, 1), diseno_stage.start_date
    assert_equal Date.new(2026, 1, 5), diseno_stage.end_date
    assert_equal Date.new(2026, 1, 6), revision_stage.start_date
    assert_equal Date.new(2026, 1, 8), revision_stage.end_date
  end

  test "apply_auto_duration! leaves a stage without dates when the profile has no duration for it" do
    field = FieldDefinition.create!(project_type: @project_type, key: "cantidad", label: "Cantidad", data_type: "number", position: 10)
    @project_type.update!(auto_stage_duration_enabled: true, duration_reference_field_definition: field)
    diseno = stage_templates(:diseno_aprobacion)
    revision = stage_templates(:revision_inicial)
    DurationProfile.create!(project_type: @project_type, operator: "between", min_value: 100, max_value: 500, durations: { diseno.id.to_s => 5 })
    project = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: { "cantidad" => "300" })

    project.apply_auto_duration!(Date.new(2026, 1, 1))

    revision_stage = project.project_stages.find_by(stage_template: revision)
    assert_nil revision_stage.start_date
  end

  test "apply_auto_duration! returns false when no profile matches" do
    field = FieldDefinition.create!(project_type: @project_type, key: "cantidad", label: "Cantidad", data_type: "number", position: 10)
    @project_type.update!(auto_stage_duration_enabled: true, duration_reference_field_definition: field)
    DurationProfile.create!(project_type: @project_type, operator: "greater_than", min_value: 1000)
    project = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: { "cantidad" => "5" })

    assert_not project.apply_auto_duration!(Date.new(2026, 1, 1))
    assert_nil project.project_stages.first.start_date
  end

  test "matching_duration_profile respects priority order (position ascending)" do
    field = FieldDefinition.create!(project_type: @project_type, key: "cantidad", label: "Cantidad", data_type: "number", position: 10)
    @project_type.update!(auto_stage_duration_enabled: true, duration_reference_field_definition: field)
    broad = DurationProfile.create!(project_type: @project_type, operator: "greater_than", min_value: 100, position: 1)
    narrow = DurationProfile.create!(project_type: @project_type, operator: "between", min_value: 100, max_value: 200, position: 0)
    project = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: { "cantidad" => "150" })

    assert_equal narrow, project.matching_duration_profile
  end

  test "creating a project with auto_duration_start_date computes stage dates via build_stages_from_template" do
    field = FieldDefinition.create!(project_type: @project_type, key: "cantidad", label: "Cantidad", data_type: "number", position: 10)
    @project_type.update!(auto_stage_duration_enabled: true, duration_reference_field_definition: field)
    diseno = stage_templates(:diseno_aprobacion)
    DurationProfile.create!(project_type: @project_type, operator: "greater_than", min_value: 1, durations: { diseno.id.to_s => 4 })

    project = Project.new(project_type: @project_type, name: "Torre Norte", custom_fields: { "cantidad" => "10" })
    project.auto_duration_start_date = "2026-02-01"
    project.save!

    diseno_stage = project.project_stages.find_by(stage_template: diseno)
    assert_equal Date.new(2026, 2, 1), diseno_stage.start_date
    assert_equal Date.new(2026, 2, 4), diseno_stage.end_date
  end

  test "creating a project without auto_duration_start_date leaves stages undated even when the type has auto duration enabled" do
    field = FieldDefinition.create!(project_type: @project_type, key: "cantidad", label: "Cantidad", data_type: "number", position: 10)
    @project_type.update!(auto_stage_duration_enabled: true, duration_reference_field_definition: field)
    diseno = stage_templates(:diseno_aprobacion)
    DurationProfile.create!(project_type: @project_type, operator: "greater_than", min_value: 1, durations: { diseno.id.to_s => 4 })

    project = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: { "cantidad" => "10" })

    assert_nil project.project_stages.find_by(stage_template: diseno).start_date
  end

  test "pending_auto_duration_start_date? is true when the first stage_template's stage has no start_date" do
    field = FieldDefinition.create!(project_type: @project_type, key: "cantidad", label: "Cantidad", data_type: "number", position: 10)
    @project_type.update!(auto_stage_duration_enabled: true, duration_reference_field_definition: field)
    project = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: {})

    assert project.pending_auto_duration_start_date?
  end

  test "pending_auto_duration_start_date? is false when the type doesn't have auto duration enabled" do
    project = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: {})
    assert_not project.pending_auto_duration_start_date?
  end

  test "pending_auto_duration_start_date? is false once the first stage already has a start_date" do
    field = FieldDefinition.create!(project_type: @project_type, key: "cantidad", label: "Cantidad", data_type: "number", position: 10)
    @project_type.update!(auto_stage_duration_enabled: true, duration_reference_field_definition: field)
    project = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: {})
    first_template = @project_type.stage_templates.min_by(&:position)
    project.project_stages.find_by(stage_template: first_template).update!(start_date: Date.new(2026, 1, 1))

    assert_not project.pending_auto_duration_start_date?
  end
```

- [ ] **Step 2: Run to confirm they fail**

Run: `bin/rails test test/models/project_test.rb`
Expected: FAIL — `NoMethodError` for `apply_auto_duration!`, `matching_duration_profile`, `auto_duration_start_date=`, `pending_auto_duration_start_date?`.

- [ ] **Step 3: Implement the calculation logic**

In `app/models/project.rb`:

Add `attr_accessor :auto_duration_start_date` right after the `accepts_nested_attributes_for` line (line 10):

```ruby
  attr_accessor :auto_duration_start_date
```

Replace `build_stages_from_template` (lines 65-69):

```ruby
  def build_stages_from_template
    project_type.stage_templates.each do |template|
      project_stages.create!(stage_template: template, name: template.name)
    end
    apply_auto_duration!(auto_duration_start_date) if project_type.auto_stage_duration_enabled? && auto_duration_start_date.present?
  end
```

Add these public methods, right after `stages_missing_dates` (after line 37, before `gantt_window`):

```ruby
  def matching_duration_profile
    field = project_type.duration_reference_field_definition
    return nil unless field
    raw = custom_fields[field.key]
    return nil if raw.blank?
    value = Float(raw)
    project_type.duration_profiles.detect { |profile| profile.matches?(value) }
  rescue ArgumentError, TypeError
    nil
  end

  def apply_auto_duration!(start_date)
    parsed_start = start_date.is_a?(Date) ? start_date : Date.parse(start_date.to_s)
    profile = matching_duration_profile
    return false unless profile

    cursor = parsed_start
    project_type.stage_templates.each do |template|
      days = profile.durations[template.id.to_s]
      next if days.blank?
      stage = project_stages.find_by(stage_template_id: template.id)
      next unless stage
      stage_end = cursor + (days.to_i - 1).days
      stage.update!(start_date: cursor, end_date: stage_end)
      cursor = stage_end + 1.day
    end
    true
  rescue ArgumentError, TypeError
    false
  end

  def pending_auto_duration_start_date?
    return false unless project_type.auto_stage_duration_enabled?
    first_template = project_type.stage_templates.min_by(&:position)
    return false unless first_template
    stage = project_stages.find { |s| s.stage_template_id == first_template.id }
    stage.present? && stage.start_date.blank?
  end
```

- [ ] **Step 4: Run the tests to confirm they pass**

Run: `bin/rails test test/models/project_test.rb`
Expected: all PASS

- [ ] **Step 5: Run the full model test suite**

Run: `bin/rails test test/models/`
Expected: all PASS, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add app/models/project.rb test/models/project_test.rb
git commit -m "Agregar cálculo de fechas automático a Project (matching_duration_profile, apply_auto_duration!)"
```

---

### Task 5: "Fecha de inicio" field on project creation

**Files:**
- Modify: `app/views/projects/_form.html.erb`
- Modify: `app/controllers/projects_controller.rb`
- Test: `test/controllers/projects_controller_test.rb`

**Interfaces:**
- Consumes: `Project#auto_duration_start_date=` (Task 4), `ProjectType#auto_stage_duration_enabled?` (Task 1).
- Produces: no new interface for later tasks.

- [ ] **Step 1: Write the failing tests**

Add to `test/controllers/projects_controller_test.rb`, near the other "new" tests (e.g. after `"new without associate_with_project_id renders an empty form as before"`):

```ruby
  test "new shows a required Fecha de inicio field when the project type has auto duration enabled" do
    project_types(:instalaciones).update!(auto_stage_duration_enabled: true)
    get new_project_path(project_type_id: project_types(:instalaciones).id)
    assert_response :success
    assert_select "input[name=?][type=date][required]", "auto_duration_start_date"
  end

  test "new does not show the Fecha de inicio field when auto duration is off" do
    get new_project_path(project_type_id: project_types(:instalaciones).id)
    assert_response :success
    assert_select "input[name=?]", "auto_duration_start_date", count: 0
  end

  test "create with auto_duration_start_date computes stage dates" do
    field = FieldDefinition.create!(project_type: project_types(:instalaciones), key: "cantidad", label: "Cantidad", data_type: "number", position: 10)
    project_types(:instalaciones).update!(auto_stage_duration_enabled: true, duration_reference_field_definition: field)
    diseno = stage_templates(:diseno_aprobacion)
    DurationProfile.create!(project_type: project_types(:instalaciones), operator: "greater_than", min_value: 1, durations: { diseno.id.to_s => 3 })

    post projects_path, params: {
      project: { project_type_id: project_types(:instalaciones).id, name: "Torre Sur", custom_fields: { cliente: "Acme S.A.", cantidad: "10" } },
      auto_duration_start_date: "2026-03-01"
    }

    project = Project.order(:id).last
    assert_redirected_to project_path(project)
    diseno_stage = project.project_stages.find_by(stage_template: diseno)
    assert_equal Date.new(2026, 3, 1), diseno_stage.start_date
    assert_equal Date.new(2026, 3, 3), diseno_stage.end_date
  end
```

- [ ] **Step 2: Run to confirm they fail**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n test_new_shows_a_required_Fecha_de_inicio_field_when_the_project_type_has_auto_duration_enabled -n test_create_with_auto_duration_start_date_computes_stage_dates`
Expected: both FAIL — the field doesn't exist in the form, and the controller never sets `auto_duration_start_date`.

(The "does not show" test should already PASS at this point — no code exists yet, so nothing renders it.)

- [ ] **Step 3: Add the field to the form**

In `app/views/projects/_form.html.erb`, insert this block right after the `:name` field's closing `</div>` (after line 19, before the `field_definitions.each` loop):

```erb
  <% if !project.persisted? && project_type.auto_stage_duration_enabled? %>
    <div class="mb-3">
      <%= label_tag :auto_duration_start_date, "Fecha de inicio", class: "form-label" %>
      <%= date_field_tag :auto_duration_start_date, nil, class: "form-control", required: true %>
      <div class="form-text">Este tipo de proyecto calcula automáticamente la duración de cada etapa a partir de esta fecha.</div>
    </div>
  <% end %>
```

- [ ] **Step 4: Wire the controller**

In `app/controllers/projects_controller.rb`, update `create` (currently lines 58-78) — add one line right after `@project = Project.new(project_params)`:

```ruby
  def create
    @project = Project.new(project_params)
    @project.auto_duration_start_date = params[:auto_duration_start_date] if params[:auto_duration_start_date].present?
    @project_type = @project.project_type
    fill_missing_shared_fields
    if @project.save
```

(Only the new second line is added; the rest of the method is unchanged.)

- [ ] **Step 5: Run the tests to confirm they pass**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n test_new_shows_a_required_Fecha_de_inicio_field_when_the_project_type_has_auto_duration_enabled -n test_new_does_not_show_the_Fecha_de_inicio_field_when_auto_duration_is_off -n test_create_with_auto_duration_start_date_computes_stage_dates`
Expected: all PASS

- [ ] **Step 6: Run the full controller test file**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: all PASS, 0 failures.

- [ ] **Step 7: Commit**

```bash
git add app/views/projects/_form.html.erb app/controllers/projects_controller.rb test/controllers/projects_controller_test.rb
git commit -m "Pedir fecha de inicio al crear un proyecto con duración automática activa"
```

---

### Task 6: Extend the "Pendientes de fecha" panel + `apply_auto_duration` action

**Files:**
- Modify: `config/routes.rb`
- Modify: `app/controllers/projects_controller.rb`
- Modify: `app/views/projects/_project_type_section.html.erb`
- Test: `test/controllers/projects_controller_test.rb`

**Interfaces:**
- Consumes: `Project#pending_auto_duration_start_date?`, `#apply_auto_duration!` (Task 4), `ProjectType#auto_stage_duration_enabled?` (Task 1).
- Produces: `POST /projects/:id/apply_auto_duration` (`apply_auto_duration_project_path`). Last task of this plan — nothing downstream depends on it.

- [ ] **Step 1: Add the route**

In `config/routes.rb`, inside the `resources :projects do ... end` block (currently lines 26-30), add a `member` block as the first line inside:

```ruby
  resources :projects do
    member { post :apply_auto_duration }
    resources :log_entries, only: [:create, :destroy]
    resources :project_responsibles, only: [:create, :destroy]
    resources :project_associations, only: [:create, :destroy]
  end
```

- [ ] **Step 2: Write the failing tests**

Add to `test/controllers/projects_controller_test.rb`, near the other index/Gantt tests for `_project_type_section` (e.g. right after the "pendientes de fecha" tests from the earlier `require-stage-dates` feature):

```ruby
  test "index shows a pending-start-date row with a date form, for auto-duration types" do
    field = FieldDefinition.create!(project_type: project_types(:instalaciones), key: "cantidad", label: "Cantidad", data_type: "number", position: 10)
    project_types(:instalaciones).update!(auto_stage_duration_enabled: true, duration_reference_field_definition: field)
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: { cantidad: "10" })
    slug = project_types(:instalaciones).slug

    get project_type_projects_path(slug)
    assert_response :success
    assert_select ".card-header", "Pendientes de fecha"
    assert_select "form[action=?]", apply_auto_duration_project_path(project) do
      assert_select "input[type=date]"
    end
  end

  test "index's pendientes de fecha panel is hidden when neither require_stage_dates nor auto_stage_duration_enabled are on" do
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_type_projects_path(project_types(:instalaciones).slug)
    assert_response :success
    assert_select ".card-header", text: "Pendientes de fecha", count: 0
  end

  test "apply_auto_duration computes and persists stage dates" do
    field = FieldDefinition.create!(project_type: project_types(:instalaciones), key: "cantidad", label: "Cantidad", data_type: "number", position: 10)
    project_types(:instalaciones).update!(auto_stage_duration_enabled: true, duration_reference_field_definition: field)
    diseno = stage_templates(:diseno_aprobacion)
    DurationProfile.create!(project_type: project_types(:instalaciones), operator: "greater_than", min_value: 1, durations: { diseno.id.to_s => 6 })
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: { cantidad: "10" })

    post apply_auto_duration_project_path(project), params: { start_date: "2026-04-01" }

    diseno_stage = project.project_stages.find_by(stage_template: diseno)
    assert_equal Date.new(2026, 4, 1), diseno_stage.reload.start_date
    assert_equal Date.new(2026, 4, 6), diseno_stage.end_date
  end

  test "apply_auto_duration redirects with an alert when no profile matches" do
    field = FieldDefinition.create!(project_type: project_types(:instalaciones), key: "cantidad", label: "Cantidad", data_type: "number", position: 10)
    project_types(:instalaciones).update!(auto_stage_duration_enabled: true, duration_reference_field_definition: field)
    DurationProfile.create!(project_type: project_types(:instalaciones), operator: "greater_than", min_value: 1000)
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: { cantidad: "5" })

    post apply_auto_duration_project_path(project), params: { start_date: "2026-04-01" }
    follow_redirect!

    assert_match(/No se pudo calcular/, response.body)
  end
```

- [ ] **Step 3: Run to confirm they fail**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n test_index_shows_a_pending_start_date_row_with_a_date_form_for_auto_duration_types -n test_apply_auto_duration_computes_and_persists_stage_dates -n test_apply_auto_duration_redirects_with_an_alert_when_no_profile_matches`
Expected: all FAIL — no such route, no such panel content yet.

(The "hidden when neither flag is on" test should already PASS — it's a regression guard for the current panel condition.)

- [ ] **Step 4: Add the controller action**

In `app/controllers/projects_controller.rb`:

Update the `before_action :set_project` line (currently `only: [:show, :edit, :update]`) to also cover the new action:

```ruby
  before_action :set_project, only: [:show, :edit, :update, :apply_auto_duration]
```

Update `before_action :authorize_edit!` (currently `only: [:edit]`):

```ruby
  before_action :authorize_edit!, only: [:edit, :apply_auto_duration]
```

Add this public action, right after `update` (after its closing `end`, before `bulk_assign_responsible`):

```ruby
  def apply_auto_duration
    if @project.apply_auto_duration!(params[:start_date])
      redirect_back fallback_location: projects_path, notice: "Fechas calculadas automáticamente."
    else
      redirect_back fallback_location: projects_path, alert: "No se pudo calcular la duración: revisá el valor de referencia y los perfiles configurados."
    end
  end
```

- [ ] **Step 5: Extend the panel**

In `app/views/projects/_project_type_section.html.erb`, replace the whole "Pendientes de fecha" block (the `<% if project_type.require_stage_dates? %> ... <% end %>` section, currently right before the "Cronograma" card):

```erb
  <% if project_type.require_stage_dates? || project_type.auto_stage_duration_enabled? %>
    <%
      pending_projects = projects_list.filter_map do |project|
        missing = project.stages_missing_dates
        needs_start = project.pending_auto_duration_start_date?
        [project, missing, needs_start] if missing.any? || needs_start
      end
    %>
    <% if pending_projects.any? %>
      <div class="card mb-4">
        <div class="card-header">Pendientes de fecha</div>
        <div class="card-body p-0">
          <ul class="list-group list-group-flush">
            <% pending_projects.each do |project, missing, needs_start| %>
              <li class="list-group-item d-flex justify-content-between align-items-center flex-wrap gap-2">
                <span>
                  <%= link_to project.name, project_path(project) %>
                  <% if missing.any? %> — falta fecha en: <%= missing.map(&:name).join(", ") %><% end %>
                </span>
                <% if needs_start %>
                  <%= form_with url: apply_auto_duration_project_path(project), method: :post, local: true, class: "d-flex gap-2 align-items-center" do |f| %>
                    <%= f.date_field :start_date, class: "form-control form-control-sm", required: true %>
                    <%= f.submit "Calcular", class: "btn btn-outline-primary btn-sm" %>
                  <% end %>
                <% end %>
              </li>
            <% end %>
          </ul>
        </div>
      </div>
    <% end %>
  <% end %>
```

- [ ] **Step 6: Run the tests to confirm they pass**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n test_index_shows_a_pending_start_date_row_with_a_date_form_for_auto_duration_types -n test_index_s_pendientes_de_fecha_panel_is_hidden_when_neither_require_stage_dates_nor_auto_stage_duration_enabled_are_on -n test_apply_auto_duration_computes_and_persists_stage_dates -n test_apply_auto_duration_redirects_with_an_alert_when_no_profile_matches`
Expected: all PASS

- [ ] **Step 7: Run the full test suite**

Run: `bin/rails test`
Expected: all PASS, 0 failures — this is the last task, so this is the full-branch regression check.

- [ ] **Step 8: Commit**

```bash
git add config/routes.rb app/controllers/projects_controller.rb app/views/projects/_project_type_section.html.erb test/controllers/projects_controller_test.rb
git commit -m "Ampliar el panel de pendientes de fecha y agregar apply_auto_duration para proyectos importados"
```
