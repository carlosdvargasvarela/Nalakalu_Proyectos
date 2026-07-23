# Carga masiva de proyectos vía CSV — design

## Contexto

Cargar proyectos uno por uno es lento cuando hay muchos pedidos que registrar de golpe. El reto es que los campos de cada proyecto son polimórficos (dependen del `ProjectType` elegido, vía `field_definitions` dinámicos) — no hay una sola "plantilla" universal, cada tipo tiene sus propias columnas.

Se usa **CSV**, no `.xlsx` real: Excel/Sheets abren y editan CSV exactamente igual que un `.xlsx` para este caso de uso (una tabla simple, sin fórmulas ni formato), y Ruby ya trae la librería `CSV` en su standard library — cero gemas nuevas, tanto para generar la plantilla como para leer el archivo subido.

## Alcance

1. **Pantalla "Importar"** — selector de tipo de proyecto, link para descargar la plantilla de ese tipo, formulario para subir el archivo lleno.
2. **Plantilla CSV por tipo** — una columna "Nombre" + una columna por cada `field_definition` del tipo (encabezado = `field.label`, orden = `field.position`).
3. **Procesamiento del archivo subido** — crea un `Project` por fila (con sus `project_stages` generadas automáticamente, igual que al crear uno manualmente — no se pisa ese mecanismo). Import **parcial**: una fila inválida no bloquea las demás; al final se muestra un reporte con cuántas se crearon y el detalle de las que fallaron (número de fila + mensaje de error).
4. **Campos `reference` en la plantilla** — se identifican por **nombre**, no por id (ej. la columna "Instalador" espera `Junior`, no un id numérico) — mismo supuesto que ya usa el resto de la app (`field.reference_table.classify.constantize`, asumiendo que el modelo referenciado expone `:name`, ya usado hoy en el `<select>` de campos `reference`).

Fuera de alcance: edición/actualización masiva de proyectos existentes vía CSV (esto es solo alta), soporte para `.xlsx` real, importar también `project_stages` con fechas/avance desde el CSV (las etapas se siguen generando vacías desde el `StageTemplate`, igual que hoy — se pueden llenar después vía Seguimiento/detalle de proyecto, ya construidos en rondas anteriores).

## 1. Rutas y controlador

```ruby
resources :imports, only: [:new, :create]
get "imports/template", to: "imports#template", as: :template_imports
```

`ImportsController`:

```ruby
class ImportsController < ApplicationController
  def new
    @project_types = ProjectType.all
    @project_type = ProjectType.find_by(id: params[:project_type_id])
  end

  def template
    project_type = ProjectType.find(params[:project_type_id])
    send_data csv_template_for(project_type), filename: "plantilla-#{project_type.slug}.csv", type: "text/csv"
  end

  def create
    project_type = ProjectType.find(params[:project_type_id])
    @results = import_rows(project_type, params[:file])
    @project_type = project_type
    @project_types = ProjectType.all
    render :new
  end

  private

  def csv_template_for(project_type)
    fields = project_type.field_definitions.order(:position)
    CSV.generate do |csv|
      csv << ["Nombre"] + fields.map(&:label)
    end
  end

  def import_rows(project_type, file)
    return { created: 0, errors: [{ row: 0, message: "No se subió ningún archivo" }] } if file.blank?

    fields = project_type.field_definitions.order(:position).to_a
    rows = CSV.parse(file.read, headers: true, encoding: "bom|utf-8")
    created = 0
    row_errors = []

    rows.each_with_index do |row, index|
      custom_fields = fields.each_with_object({}) do |field, hash|
        hash[field.key] = resolve_field_value(field, row[field.label])
      end
      project = Project.new(project_type: project_type, name: row["Nombre"], custom_fields: custom_fields)
      if project.save
        created += 1
      else
        row_errors << { row: index + 2, message: project.errors.full_messages.join(", ") }
      end
    end

    { created: created, errors: row_errors }
  end

  def resolve_field_value(field, raw_value)
    return raw_value if raw_value.blank? || field.data_type != "reference"

    record = field.reference_table.classify.constantize.find_by(name: raw_value.strip)
    record ? record.id : "#{raw_value} (no encontrado)"
  end
end
```

(`resolve_field_value` para campos `reference`: si no encuentra el nombre, deja un valor que a propósito **no** es un id válido — así la validación existente de `Project` (`valid_reference?`, ya implementada) lo rechaza con un mensaje claro en vez de guardar una referencia rota. El número de fila reportado (`index + 2`) cuenta el encabezado como fila 1, igual que se ve al abrir el CSV en Excel.)

## 2. Vista `imports/new.html.erb`

```erb
<h1>Importar proyectos</h1>

<%= form_with url: new_import_path, method: :get, local: true, class: "row g-2 mb-4" do |form| %>
  <div class="col-auto">
    <%= form.label :project_type_id, "Tipo de proyecto", class: "form-label" %>
    <%= form.select :project_type_id, @project_types.collect { |pt| [pt.name, pt.id] },
          { selected: @project_type&.id, include_blank: "Elegí un tipo" }, class: "form-select" %>
  </div>
  <div class="col-auto align-self-end">
    <%= form.submit "Ver plantilla", class: "btn btn-outline-secondary" %>
  </div>
<% end %>

<% if @project_type %>
  <div class="card mb-4">
    <div class="card-body">
      <p>
        1. <%= link_to "Descargar plantilla de #{@project_type.name}", template_imports_path(project_type_id: @project_type.id) %>
      </p>
      <p>2. Llená una fila por proyecto. La columna "Nombre" es obligatoria.</p>

      <%= form_with url: imports_path, method: :post, local: true, multipart: true do |form| %>
        <%= form.hidden_field :project_type_id, value: @project_type.id %>
        <div class="mb-3">
          <%= form.label :file, "Archivo lleno (CSV)", class: "form-label" %>
          <%= form.file_field :file, class: "form-control", accept: ".csv" %>
        </div>
        <%= form.submit "Importar", class: "btn btn-primary" %>
      <% end %>
    </div>
  </div>
<% end %>

<% if @results %>
  <div class="alert <%= @results[:errors].any? ? 'alert-warning' : 'alert-success' %>">
    <%= @results[:created] %> proyecto(s) creado(s).
    <% if @results[:errors].any? %>
      <p class="mb-0 mt-2">Filas con error:</p>
      <ul class="mb-0">
        <% @results[:errors].each do |error| %>
          <li>Fila <%= error[:row] %>: <%= error[:message] %></li>
        <% end %>
      </ul>
    <% end %>
  </div>
<% end %>
```

## 3. Entrada de navegación

Link "Importar" en `app/views/layouts/_navbar.html.erb`, junto a "Proyectos"/"Seguimiento".

## Testing

- Controlador: `template` — genera un CSV con la columna "Nombre" + una por cada `field_definition` del tipo, en el orden correcto.
- Controlador: `create` — sube un CSV válido con 2 filas → crea 2 proyectos, cada uno con sus `project_stages` (igual que la creación manual), reporta `created: 2, errors: []`.
- Controlador: `create` — una fila con `Nombre` en blanco no crea el proyecto y aparece en `errors` con el número de fila correcto.
- Controlador: `create` — una fila con un valor de campo `reference` que no existe (ej. instalador inexistente) no crea el proyecto y el mensaje de error lo indica.
- Controlador: `create` — import parcial: de 3 filas, 1 inválida, se crean las otras 2 y se reporta el error de la tercera (no aborta todo el lote).
- Controlador: sin archivo subido — reporta el error correspondiente sin lanzar una excepción.

## Edge cases

- Un tipo de proyecto sin ningún `field_definition`: la plantilla es solo la columna "Nombre" — sigue funcionando, cada fila crea un proyecto solo con nombre y `custom_fields` vacío.
- Un CSV con columnas en distinto orden al de la plantilla: no importa — se busca cada columna **por nombre de encabezado** (`row[field.label]`), no por posición.
- Un CSV con columnas extra que no corresponden a ningún campo: se ignoran silenciosamente (no rompen el import).
- Fila con todos los campos vacíos salvo "Nombre": igual que crear un proyecto manual con `custom_fields` vacío — válido (los campos no son obligatorios salvo que su propio tipo de dato lo exija, comportamiento ya existente en `Project`).
