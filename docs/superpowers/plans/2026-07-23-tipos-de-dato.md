# Nuevos tipos de dato + traducción del selector — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 4 new field data types (`number`, `currency`, `textarea`, `boolean`) and fix the "Tipo de dato" selector showing raw English values as both value and label — same gap already fixed for status/progress elsewhere in the app.

**Architecture:** Task 1 covers the model layer (`FieldDefinition::DATA_TYPES`/`DATA_TYPE_LABELS`, `Project`'s validation for the new types) and the two admin views that display a data type. Task 2 covers the actual per-type input rendering in the dynamic project form (`_field_input.html.erb`).

**Tech Stack:** Ruby on Rails, Minitest + fixtures. No new gems, no migrations (`data_type` is already a plain string column; the CSV importer needs no changes — it already passes raw strings through to `custom_fields` regardless of type, relying on `Project`'s validation, same as this plan's new types).

## Global Constraints

- Existing data type values (`text`, `date`, `percent`, `reference`) keep their exact string values — only their *label* changes, no data migration.
- Native HTML5 `number` inputs (`number_field_tag`) are the client-side guard for numeric types — but server-side validation in `Project#custom_fields_match_definitions` is still required (HTML can be bypassed) and must reject non-numeric values for `number`/`currency`.
- `valid_boolean?` accepts `"true"`/`"false"` case-insensitively (covers both the web checkbox, which always submits lowercase `"true"`, and a value typed by hand into an imported CSV).

---

### Task 1: Model layer — new types, Spanish labels, validation

**Files:**
- Modify: `app/models/field_definition.rb`
- Modify: `app/models/project.rb`
- Modify: `app/views/admin/field_definitions/_form.html.erb`
- Modify: `app/views/admin/project_types/show.html.erb`
- Modify: `test/models/field_definition_test.rb`
- Modify: `test/models/project_test.rb`
- Modify: `test/controllers/admin/project_types_controller_test.rb`

**Interfaces:**
- Consumes: nothing new.
- Produces: `FieldDefinition::DATA_TYPES` (expanded to 8 entries), `FieldDefinition::DATA_TYPE_LABELS`, `FieldDefinition#data_type_label`, `Project`'s validation now accepting `number`/`currency`/`textarea`/`boolean`. Task 2 consumes all of these when rendering the dynamic form.

- [ ] **Step 1: Write the failing model tests**

Add to `test/models/field_definition_test.rb`, inside the existing test class:

```ruby
  test "data_type_label translates every known type to Spanish" do
    expected = {
      "text" => "Texto", "textarea" => "Texto largo", "number" => "Número",
      "currency" => "Monto (₡)", "percent" => "Porcentaje", "date" => "Fecha",
      "boolean" => "Sí/No", "reference" => "Referencia"
    }
    expected.each do |data_type, label|
      field = FieldDefinition.new(project_type: project_types(:instalaciones), key: "x", label: "X", data_type: data_type)
      assert_equal label, field.data_type_label
    end
  end

  test "data_type_label falls back to the raw value for an unknown type" do
    field = FieldDefinition.new(project_type: project_types(:instalaciones), key: "x", label: "X", data_type: "text")
    field.data_type = "weird_type"
    assert_equal "weird_type", field.data_type_label
  end

  test "valid with each of the new data types" do
    %w[number currency textarea boolean].each do |data_type|
      field = FieldDefinition.new(
        project_type: project_types(:instalaciones), key: "campo_#{data_type}", label: "Campo", data_type: data_type
      )
      assert field.valid?, "#{data_type}: #{field.errors.full_messages}"
    end
  end
```

Add to `test/models/project_test.rb`, inside the existing test class:

```ruby
  test "valid with correct values for the new data types" do
    FieldDefinition.create!(project_type: @project_type, key: "cantidad", label: "Cantidad", data_type: "number", position: 10)
    FieldDefinition.create!(project_type: @project_type, key: "monto", label: "Monto", data_type: "currency", position: 11)
    FieldDefinition.create!(project_type: @project_type, key: "notas", label: "Notas", data_type: "textarea", position: 12)
    FieldDefinition.create!(project_type: @project_type, key: "permiso", label: "Permiso", data_type: "boolean", position: 13)

    project = Project.new(
      project_type: @project_type, name: "Torre Norte",
      custom_fields: { "cantidad" => "3", "monto" => "1500.50", "notas" => "Cliente pidió instalación urgente", "permiso" => "true" }
    )
    assert project.valid?, project.errors.full_messages.to_s
  end

  test "invalid when a number or currency field isn't numeric" do
    FieldDefinition.create!(project_type: @project_type, key: "cantidad", label: "Cantidad", data_type: "number", position: 10)
    project = Project.new(
      project_type: @project_type, name: "Torre Norte", custom_fields: { "cantidad" => "no es un número" }
    )
    assert_not project.valid?
  end

  test "invalid when a boolean field isn't true or false" do
    FieldDefinition.create!(project_type: @project_type, key: "permiso", label: "Permiso", data_type: "boolean", position: 10)
    project = Project.new(
      project_type: @project_type, name: "Torre Norte", custom_fields: { "permiso" => "tal vez" }
    )
    assert_not project.valid?
  end

  test "valid when a boolean field is True or FALSE (case-insensitive)" do
    FieldDefinition.create!(project_type: @project_type, key: "permiso", label: "Permiso", data_type: "boolean", position: 10)
    project = Project.new(
      project_type: @project_type, name: "Torre Norte", custom_fields: { "permiso" => "True" }
    )
    assert project.valid?, project.errors.full_messages.to_s
  end

  test "valid when a textarea field is a plain string" do
    FieldDefinition.create!(project_type: @project_type, key: "notas", label: "Notas", data_type: "textarea", position: 10)
    project = Project.new(
      project_type: @project_type, name: "Torre Norte", custom_fields: { "notas" => "una nota larga" }
    )
    assert project.valid?, project.errors.full_messages.to_s
  end
```

Add to `test/controllers/admin/project_types_controller_test.rb`, inside the existing test class:

```ruby
  test "show displays the Spanish label for a field's data type, not the raw value" do
    get admin_project_type_path(project_types(:instalaciones))
    assert_response :success
    assert_select "body", /Texto/
    assert_no_match(/\(text\)/, response.body)
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/models/field_definition_test.rb test/models/project_test.rb test/controllers/admin/project_types_controller_test.rb`
Expected: FAIL — `NoMethodError: undefined method 'data_type_label'`, and `number`/`currency`/`textarea`/`boolean` are rejected by the current `DATA_TYPES` inclusion validation.

- [ ] **Step 3: Expand `FieldDefinition`**

Edit `app/models/field_definition.rb`:

```ruby
class FieldDefinition < ApplicationRecord
  DATA_TYPES = %w[text textarea number currency percent date boolean reference].freeze
  DATA_TYPE_LABELS = {
    "text" => "Texto",
    "textarea" => "Texto largo",
    "number" => "Número",
    "currency" => "Monto (₡)",
    "percent" => "Porcentaje",
    "date" => "Fecha",
    "boolean" => "Sí/No",
    "reference" => "Referencia"
  }.freeze

  belongs_to :project_type

  validates :key, presence: true, uniqueness: { scope: :project_type_id }
  validates :label, presence: true
  validates :data_type, inclusion: { in: DATA_TYPES }
  validates :reference_table, presence: true, if: -> { data_type == "reference" }

  def data_type_label
    DATA_TYPE_LABELS.fetch(data_type, data_type)
  end
end
```

- [ ] **Step 4: Add validation for the new types in `Project`**

Edit `app/models/project.rb` — replace the `custom_fields_match_definitions` method:

```ruby
  def custom_fields_match_definitions
    project_type.field_definitions.each do |field|
      value = custom_fields[field.key]
      next if value.nil? || value == ""

      case field.data_type
      when "text", "textarea"
        errors.add(:custom_fields, "#{field.label} debe ser texto") unless value.is_a?(String)
      when "date"
        errors.add(:custom_fields, "#{field.label} debe ser una fecha válida") unless valid_date?(value)
      when "percent"
        errors.add(:custom_fields, "#{field.label} debe ser un porcentaje entre 0 y 100") unless valid_percent?(value)
      when "number", "currency"
        errors.add(:custom_fields, "#{field.label} debe ser un número") unless valid_number?(value)
      when "boolean"
        errors.add(:custom_fields, "#{field.label} debe ser Sí o No") unless valid_boolean?(value)
      when "reference"
        errors.add(:custom_fields, "#{field.label} debe referenciar un registro existente") unless valid_reference?(field, value)
      end
    end
  end
```

Add these two private methods, right after `valid_percent?`:

```ruby
  def valid_number?(value)
    Float(value)
    true
  rescue ArgumentError, TypeError
    false
  end

  def valid_boolean?(value)
    %w[true false].include?(value.to_s.downcase)
  end
```

- [ ] **Step 5: Run the model tests to verify they pass**

Run: `bin/rails test test/models/field_definition_test.rb test/models/project_test.rb`
Expected: PASS (all tests)

- [ ] **Step 6: Fix the two admin views**

Edit `app/views/admin/field_definitions/_form.html.erb` — replace:

```erb
    <%= form.select :data_type, FieldDefinition::DATA_TYPES, {}, class: "form-select" %>
```

with:

```erb
    <%= form.select :data_type, FieldDefinition::DATA_TYPES.map { |dt| [FieldDefinition::DATA_TYPE_LABELS[dt], dt] }, {}, class: "form-select" %>
```

Edit `app/views/admin/project_types/show.html.erb` — replace:

```erb
          <span><%= field.label %> (<%= field.data_type %>)</span>
```

with:

```erb
          <span><%= field.label %> (<%= field.data_type_label %>)</span>
```

- [ ] **Step 7: Run the controller test to verify it passes**

Run: `bin/rails test test/controllers/admin/project_types_controller_test.rb`
Expected: PASS (all tests)

- [ ] **Step 8: Run the full suite**

Run: `bin/rails test`
Expected: PASS

- [ ] **Step 9: Commit**

```bash
git add app/models/field_definition.rb app/models/project.rb app/views/admin/field_definitions/_form.html.erb \
  app/views/admin/project_types/show.html.erb test/models/field_definition_test.rb test/models/project_test.rb \
  test/controllers/admin/project_types_controller_test.rb
git commit -m "Add number/currency/textarea/boolean field types, translate the Tipo de dato selector"
```

---

### Task 2: Render the right input per type in the project form

**Files:**
- Modify: `app/views/projects/_field_input.html.erb`
- Modify: `test/controllers/projects_controller_test.rb`

**Interfaces:**
- Consumes: `FieldDefinition::DATA_TYPES`/`#data_type` (Task 1, already committed).
- Produces: nothing consumed by a later task — this is the last task in the plan.

- [ ] **Step 1: Write the failing tests**

Add to `test/controllers/projects_controller_test.rb`, inside the existing test class:

```ruby
  test "new renders the right input for each new data type" do
    project_type = project_types(:instalaciones)
    FieldDefinition.create!(project_type: project_type, key: "cantidad", label: "Cantidad", data_type: "number", position: 10)
    FieldDefinition.create!(project_type: project_type, key: "monto", label: "Monto", data_type: "currency", position: 11)
    FieldDefinition.create!(project_type: project_type, key: "notas", label: "Notas", data_type: "textarea", position: 12)
    FieldDefinition.create!(project_type: project_type, key: "permiso", label: "Permiso", data_type: "boolean", position: 13)

    get new_project_path(project_type_id: project_type.id)
    assert_response :success
    assert_select "input[name=?][type=number]", "project[custom_fields][cantidad]"
    assert_select "input[name=?][type=number]", "project[custom_fields][monto]"
    assert_select "textarea[name=?]", "project[custom_fields][notas]"
    assert_select "input[name=?][type=checkbox]", "project[custom_fields][permiso]"
  end

  test "create with valid new-type custom_fields builds the project" do
    project_type = project_types(:instalaciones)
    FieldDefinition.create!(project_type: project_type, key: "cantidad", label: "Cantidad", data_type: "number", position: 10)

    assert_difference("Project.count", 1) do
      post projects_path, params: {
        project: {
          project_type_id: project_type.id, name: "Torre Sur",
          custom_fields: { cliente: "Acme S.A.", cantidad: "5" }
        }
      }
    end
    assert_equal "5", Project.order(:id).last.custom_fields["cantidad"]
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: FAIL — `_field_input.html.erb`'s `case` statement has no branch for `number`/`currency`/`textarea`/`boolean`, so nothing renders for those fields yet.

- [ ] **Step 3: Update `_field_input.html.erb`**

Replace `app/views/projects/_field_input.html.erb` in full:

```erb
<div class="mb-3">
  <%= label_tag "project_custom_fields_#{field.key}", field.label, class: "form-label" %>
  <% case field.data_type %>
  <% when "text" %>
    <%= text_field_tag "project[custom_fields][#{field.key}]", project.custom_fields[field.key], class: "form-control" %>
  <% when "textarea" %>
    <%= text_area_tag "project[custom_fields][#{field.key}]", project.custom_fields[field.key], class: "form-control", rows: 3 %>
  <% when "date" %>
    <%= date_field_tag "project[custom_fields][#{field.key}]", project.custom_fields[field.key], class: "form-control" %>
  <% when "percent" %>
    <%= number_field_tag "project[custom_fields][#{field.key}]", project.custom_fields[field.key], min: 0, max: 100, class: "form-control" %>
  <% when "number" %>
    <%= number_field_tag "project[custom_fields][#{field.key}]", project.custom_fields[field.key], step: "any", class: "form-control" %>
  <% when "currency" %>
    <div class="input-group">
      <span class="input-group-text">₡</span>
      <%= number_field_tag "project[custom_fields][#{field.key}]", project.custom_fields[field.key], step: "0.01", class: "form-control" %>
    </div>
  <% when "boolean" %>
    <div class="form-check">
      <%= check_box_tag "project[custom_fields][#{field.key}]", "true", project.custom_fields[field.key].to_s == "true", class: "form-check-input" %>
    </div>
  <% when "reference" %>
    <%= select_tag "project[custom_fields][#{field.key}]",
          options_from_collection_for_select(field.reference_table.classify.constantize.all, :id, :name, project.custom_fields[field.key]),
          { include_blank: true, class: "form-select" } %>
  <% end %>
</div>
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: PASS (all tests)

- [ ] **Step 5: Run the full suite**

Run: `bin/rails test`
Expected: PASS

- [ ] **Step 6: Manual verification**

Run: `bin/rails server`:
- In Administración → un tipo de proyecto → Campos, agregar un campo con cada tipo nuevo (Número, Monto, Texto largo, Sí/No) — confirmar que el `<select>` de "Tipo de dato" ya muestra las 8 opciones en español.
- Crear un proyecto de ese tipo — confirmar que cada campo nuevo se ve con el input correcto (numérico con flechitas, el de Monto con el símbolo ₡ al lado, el de texto largo como área multilínea, el de Sí/No como checkbox).
- Intentar escribir letras en el campo Número o Monto — confirmar que el navegador las rechaza (comportamiento nativo del input `type="number"`).
- Guardar el proyecto y volver a editarlo — confirmar que los valores se mantienen correctamente en cada input.

- [ ] **Step 7: Commit**

```bash
git add app/views/projects/_field_input.html.erb test/controllers/projects_controller_test.rb
git commit -m "Render number/currency/textarea/boolean inputs in the dynamic project form"
```

---

## Final verification

- [ ] Run `bin/rails test` once more — expect a clean pass.
- [ ] `grep -n "data_type %>)" app/views/admin/project_types/show.html.erb` returns nothing (confirms the raw-value display is fully gone, replaced by `data_type_label`).
