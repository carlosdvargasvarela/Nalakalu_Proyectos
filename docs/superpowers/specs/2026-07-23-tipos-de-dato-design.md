# Nuevos tipos de dato para campos + traducción del selector — design

## Contexto

Revisando Administración → Campos, el `<select>` de "Tipo de dato" muestra los valores crudos del enum (`text`, `date`, `percent`, `reference`) tanto como valor **y como texto visible** — nunca se tradujo, a diferencia de Estado/Avance que ya tienen su mapeo a español. Aprovechando ese arreglo, se agregan los tipos de dato que hacían falta: Monto/Moneda, Número simple, Texto largo, y Sí/No.

## Alcance

1. **4 tipos de dato nuevos** en `FieldDefinition::DATA_TYPES`: `number`, `currency`, `textarea`, `boolean`.
2. **Traducción de todos los tipos** (nuevos y existentes) — un mapeo `data_type → etiqueta en español`, usado en el `<select>` de Administración y en la lista de campos del tipo de proyecto (que hoy también muestra el valor crudo).
3. **Inputs correctos por tipo** en el formulario dinámico de proyecto (`_field_input.html.erb`) — los numéricos (`number`, `currency`, y el `percent` ya existente) usan `number_field` (HTML5 nativo: rechaza letras, teclado numérico en celular), `textarea` usa un área de texto, `boolean` un checkbox.
4. **Validación del lado del servidor** para los 4 tipos nuevos en `Project#custom_fields_match_definitions` — el input nativo ayuda mucho, pero no es suficiente por sí solo (se puede editar el HTML, pegar texto, etc.), así que se valida igual que ya se hace para `date`/`percent`/`reference`.

Fuera de alcance: cambiar el importador CSV (no necesita cambios — ya pasa cualquier valor de texto crudo a `custom_fields`, y la validación del modelo lo revisa igual sin importar si vino del formulario web o de un CSV), formato de miles/separador de coma para `currency` en el input (el input nativo de HTML5 no soporta eso bien; se muestra como número simple con símbolo ₡ al lado, sin comas — consistente con lo que ya hace `percent`).

## 1 y 2. `FieldDefinition`

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

`app/views/admin/field_definitions/_form.html.erb` — el `<select>` pasa de:

```erb
<%= form.select :data_type, FieldDefinition::DATA_TYPES, {}, class: "form-select" %>
```

a:

```erb
<%= form.select :data_type, FieldDefinition::DATA_TYPES.map { |dt| [FieldDefinition::DATA_TYPE_LABELS[dt], dt] }, {}, class: "form-select" %>
```

(El valor guardado sigue siendo el string crudo en inglés — `"number"`, `"currency"`, etc. — solo cambia el texto que ve el usuario en el `<option>`. No hay migración de datos: los tipos existentes (`text`, `date`, `percent`, `reference`) no cambian de valor, solo ganan una etiqueta.)

`app/views/admin/project_types/show.html.erb` — la lista de campos pasa de:

```erb
<span><%= field.label %> (<%= field.data_type %>)</span>
```

a:

```erb
<span><%= field.label %> (<%= field.data_type_label %>)</span>
```

## 3. `_field_input.html.erb` — un input por tipo

```erb
<div class="mb-3">
  <%= label_tag "project_custom_fields_#{field.key}", field.label, class: "form-label" %>
  <% case field.data_type %>
  <% when "text", "textarea" %>
    <% if field.data_type == "textarea" %>
      <%= text_area_tag "project[custom_fields][#{field.key}]", project.custom_fields[field.key], class: "form-control", rows: 3 %>
    <% else %>
      <%= text_field_tag "project[custom_fields][#{field.key}]", project.custom_fields[field.key], class: "form-control" %>
    <% end %>
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

(`number_field_tag` es un `<input type="number">` nativo — el navegador ya bloquea letras al escribir, muestra flechitas +/- y teclado numérico en celular. `step: "any"`/`"0.01"` permite decimales; `percent` mantiene su `min`/`max` 0-100 que ya tenía.)

## 4. Validación en `Project`

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

Nuevos métodos privados:

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

(`valid_boolean?` acepta `"true"`/`"false"` sin distinguir mayúsculas — cubre tanto el checkbox del formulario web, que siempre manda `"true"` en minúscula cuando está marcado, como alguien escribiendo `"True"`/`"FALSE"` a mano en un CSV importado.)

## Testing

- Modelo: `FieldDefinition#data_type_label` — traduce cada uno de los 8 tipos; devuelve el valor crudo para uno desconocido (mismo patrón que `status_label`/`progress_status_label`).
- Modelo: `FieldDefinition` — sigue validando `data_type` contra la lista ampliada (un valor fuera de la lista sigue siendo inválido).
- Modelo: `Project` — válido/inválido para cada tipo nuevo (`number` con un valor no numérico, `currency` igual, `boolean` con un valor que no sea `"true"`/`"false"`), más el caso ya existente de `text`/`textarea` con un valor no-String.
- Controlador: `admin/field_definitions` — el formulario nuevo/editar muestra las 8 opciones en español; la lista de campos en `project_types#show` muestra la etiqueta en español, no el valor crudo.
- Controlador: `projects#new`/`#edit` — se renderiza el input correcto por cada tipo nuevo (number/currency/boolean/textarea) con los atributos HTML esperados (`type="number"`, `<textarea>`, checkbox).

## Edge cases

- Un campo `boolean` sin marcar en el formulario: el checkbox no manda ningún valor (comportamiento HTML estándar) — `custom_fields[field.key]` queda ausente, tratado igual que cualquier otro campo "en blanco, sin responder" (el `next if value.nil? || value == ""` ya existente lo cubre, sin necesidad de un valor `"false"` explícito).
- Un valor `currency`/`number` con coma en vez de punto decimal (ej. alguien escribe `"3,50"` a mano en un CSV importado, no vía el input nativo): `Float("3,50")` lanza `ArgumentError`, el campo se marca inválido con un mensaje claro — no se intenta adivinar el formato regional, consistente con cómo ya se comporta `percent` hoy.
