# Carga masiva: soporte Excel + vista previa de errores — design

## Contexto

El import actual (`ImportsController`, ver `docs/superpowers/specs/2026-07-23-importar-proyectos-design.md`) solo acepta CSV y guarda las filas válidas al toque, mostrando errores recién después de que ya se procesó todo. Dos problemas a resolver:

1. El equipo maneja los datos en Excel real (`.xlsx`), no CSV — hoy tienen que exportar a CSV a mano antes de poder importar.
2. No hay forma de revisar errores **antes** de que el import ya haya guardado lo que pudo guardar — si el archivo tiene problemas, el usuario se entera después de que una parte ya se creó.

## Alcance

1. **Aceptar `.xlsx` además de `.csv`**, detectado por extensión del archivo subido. Se agrega la gema `roo` (lectura de xlsx; CSV se sigue leyendo con la librería `csv` de siempre). `.xls` (formato viejo) queda fuera de alcance: `roo` 3.0 ya no lo soporta sin la gema aparte `roo-xls`.
2. **Paso de vista previa**: subir el archivo ya no guarda nada. Se parsean y validan todas las filas contra el `ProjectType` elegido, y se muestra una tabla con el contenido de cada fila y, si aplica, su error — sin tocar la base de datos.
3. **Paso de confirmación**: un botón "Confirmar importación" en la pantalla de preview reenvía las filas que pasaron validación (serializadas en un campo oculto) y recién ahí se crean los `Project` (con su `ProjectAccess` para gerentes, igual que hoy). Las filas con error no se reenvían — no se reprocesa el archivo original.
4. **Import parcial** (sin cambios de comportamiento): de las filas confirmadas, todas pasaron validación en el preview, así que todas se crean. Si igualmente alguna falla al guardar en el paso de confirmación (carrera muy improbable, ej. el registro referenciado se borró entre preview y confirmar), se reporta igual que hoy (no aborta el resto).

Fuera de alcance: edición/actualización masiva de proyectos existentes, importar fórmulas/formato de Excel (solo se leen valores de celda), soporte de múltiples hojas por archivo (se usa siempre la primera hoja/`default_sheet`), persistir el preview en el servidor (sesión, archivo temporal) — se resuelve reenviando el JSON de filas válidas en el propio formulario de confirmación.

## 1. Gema nueva

```ruby
# Gemfile
gem "roo" # lectura de .xlsx para carga masiva; CSV sigue usando la stdlib
```

## 2. Rutas

```ruby
resources :imports, only: [:new, :create] do
  collection do
    get :template
    post :preview
  end
end
```

- `GET /imports/template` — sin cambios.
- `POST /imports/preview` — nuevo: recibe el archivo, devuelve la vista previa.
- `POST /imports` (`create`) — cambia de significado: ahora es el paso de **confirmación**, recibe las filas ya validadas (no un archivo).

## 3. Controlador

`ImportsController` sigue concentrando toda la lógica (sin servicios/jobs nuevos, mismo criterio que el import original).

```ruby
require "csv"
require "roo"

class ImportsController < ApplicationController
  before_action :require_admin_or_gerente!

  def new
    @project_types = ProjectType.all
    @project_type = ProjectType.find_by(id: params[:project_type_id])
  end

  def template
    # sin cambios
  end

  def preview
    @project_type = ProjectType.find(params[:project_type_id])
    @project_types = ProjectType.all
    @preview = build_preview(@project_type, params[:file])
    render :new
  end

  def create
    @project_type = ProjectType.find(params[:project_type_id])
    @project_types = ProjectType.all
    valid_rows = JSON.parse(params[:valid_rows] || "[]")
    @results = commit_rows(@project_type, valid_rows)
    render :new
  end

  private

  def csv_template_for(project_type)
    # sin cambios
  end

  # Devuelve { valid_rows_json:, rows: [{ row:, name:, custom_fields:, error: }] }
  # rows sin error tienen error: nil; valid_rows_json es lo que viaja en el form de confirmación.
  def build_preview(project_type, file)
    return { rows: [{ row: 0, error: "No se subió ningún archivo" }], valid_rows_json: "[]" } if file.blank?

    fields = project_type.field_definitions.order(:position).to_a
    parsed_rows = parse_rows(file, fields)
    rows = []
    valid_rows = []

    parsed_rows.each_with_index do |(name, custom_fields), index|
      row_number = index + 2
      project = Project.new(project_type: project_type, name: name, custom_fields: custom_fields)
      if project.valid?
        rows << { row: row_number, name: name, custom_fields: custom_fields, error: nil }
        valid_rows << { row: row_number, name: name, custom_fields: custom_fields }
      else
        rows << { row: row_number, name: name, custom_fields: custom_fields, error: project.errors.full_messages.join(", ") }
      end
    end

    { rows: rows, valid_rows_json: valid_rows.to_json }
  end

  def commit_rows(project_type, valid_rows)
    created = 0
    row_errors = []

    valid_rows.each do |row|
      project = Project.new(project_type: project_type, name: row["name"], custom_fields: row["custom_fields"] || {})
      if project.save
        ProjectAccess.create!(user: current_user, project: project, can_edit: true) if current_user.gerente?
        created += 1
      else
        row_errors << { row: row["row"], message: project.errors.full_messages.join(", ") }
      end
    end

    { created: created, errors: row_errors }
  end

  # Devuelve un array de [name, custom_fields_hash], uno por fila de datos (sin encabezado),
  # sea el archivo .csv o .xlsx.
  def parse_rows(file, fields)
    extension = File.extname(file.original_filename).downcase

    if extension == ".csv"
      CSV.parse(file.read.force_encoding("UTF-8").sub("﻿", ""), headers: true).map do |row|
        [row["Nombre"], fields.each_with_object({}) { |f, h| h[f.key] = resolve_field_value(f, row[f.label]) }]
      end
    else
      sheet = Roo::Spreadsheet.open(file.path, extension: extension.delete(".").to_sym).sheet(0)
      header = sheet.row(1)
      (2..sheet.last_row).map do |i|
        row = header.zip(sheet.row(i)).to_h
        [row["Nombre"], fields.each_with_object({}) { |f, h| h[f.key] = resolve_field_value(f, row[f.label]) }]
      end
    end
  end

  def resolve_field_value(field, raw_value)
    # sin cambios
  end
end
```

Notas:
- `Roo::Spreadsheet.open` necesita un path en disco; `Rack::Test::UploadedFile`/`ActionDispatch::Http::UploadedFile` ya exponen `.path` (tempfile), así que no hace falta guardar nada aparte.
- El número de fila (`index + 2`) se calcula una sola vez en `build_preview` y viaja como `row:` dentro de cada fila de `valid_rows_json`; `commit_rows` lo reusa tal cual (`row["row"]`) en vez de recalcularlo sobre el array ya filtrado — así un error al confirmar sigue apuntando a la fila real del archivo, no a su posición entre las filas válidas.
- `resolve_field_value` no cambia: sigue resolviendo `reference` por nombre.

## 4. Vista `imports/new.html.erb`

Estructura en 3 bloques condicionales, todo en la misma vista (igual criterio que hoy):

1. Selector de tipo + link de plantilla (sin cambios).
2. Si NO hay `@preview` ni `@results`: formulario de subida, ahora apunta a `preview_imports_path` y acepta `.csv,.xlsx`.
3. Si hay `@preview`: tabla con una fila por registro del archivo (columnas: fila, nombre, cada custom field, error) — filas con error resaltadas (`table-danger`); debajo, un form oculto con `valid_rows_json` que postea a `imports_path` (create) con botón "Confirmar importación" (deshabilitado/oculto si no hay ninguna fila válida) y un link para volver a intentar subir el archivo.
4. Si hay `@results` (después de confirmar): mismo bloque de resultado que existe hoy (`created`/`errors`).

```erb
<% if @preview %>
  <div class="card mb-4">
    <div class="card-body">
      <h2 class="h5">Vista previa</h2>
      <table class="table table-sm">
        <thead>
          <tr>
            <th>Fila</th>
            <th>Nombre</th>
            <th>Error</th>
          </tr>
        </thead>
        <tbody>
          <% @preview[:rows].each do |row| %>
            <tr class="<%= 'table-danger' if row[:error] %>">
              <td><%= row[:row] %></td>
              <td><%= row[:name] %></td>
              <td><%= row[:error] %></td>
            </tr>
          <% end %>
        </tbody>
      </table>

      <% if @preview[:rows].any? { |r| r[:error].nil? } %>
        <%= form_with url: imports_path, method: :post, local: true do |form| %>
          <%= form.hidden_field :project_type_id, value: @project_type.id %>
          <%= form.hidden_field :valid_rows, value: @preview[:valid_rows_json] %>
          <%= form.submit "Confirmar importación", class: "btn btn-primary" %>
        <% end %>
      <% else %>
        <p class="text-muted">Ninguna fila es válida — corregí el archivo y volvé a subirlo.</p>
      <% end %>
    </div>
  </div>
<% end %>
```

## 5. Testing

Minitest, mismo patrón que el test existente (`Rack::Test::UploadedFile`).

- `preview` con un `.csv` de 2 filas válidas → no crea ningún `Project`, muestra ambas filas sin error y el botón de confirmar.
- `preview` con un `.xlsx` de 2 filas válidas → mismo resultado que el CSV equivalente (nuevo fixture binario en `test/fixtures/files/`).
- `preview` con una fila con `Nombre` en blanco → esa fila se muestra con error, no crea nada.
- `preview` sin archivo → mensaje "No se subió ningún archivo", no crea nada.
- `create` con `valid_rows` de 2 filas → crea 2 `Project`s con sus `custom_fields` y stages, igual que el test existente.
- `create` como gerente → sigue creando `ProjectAccess` con `can_edit: true`.
- `new` sigue bloqueado para visor (sin cambios, ya cubierto).

## Edge cases

- `.xlsx` con columnas en otro orden que la plantilla: se buscan por encabezado (`row["Nombre"]`, `row[field.label]`), igual que CSV — no importa el orden.
- `.xls` (formato viejo de Excel): fuera de alcance — `roo` 3.0 no lo soporta sin la gema aparte `roo-xls`; se trata como extensión no reconocida.
- Extensión de archivo no reconocida (ni `.csv` ni `.xlsx`): se trata como si no se hubiera subido archivo, con mensaje "Formato no soportado, subí un .csv o .xlsx".
- Archivo `.xlsx` corrupto/mal formado (no es un zip válido) o CSV malformado: `parse_rows` puede lanzar cualquier excepción de parseo (ej. `Zip::Error`, `CSV::MalformedCSVError`); `build_preview` rescata `StandardError` en general y muestra "No se pudo leer el archivo" en vez de un 500.
- Confirmar dos veces el mismo formulario (doble click): crea los proyectos dos veces — mismo comportamiento que ya existía implícitamente al reenviar un POST; fuera de alcance resolverlo acá (no lo maneja tampoco el import original).
