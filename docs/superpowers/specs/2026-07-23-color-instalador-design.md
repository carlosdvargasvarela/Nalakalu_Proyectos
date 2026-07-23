# Color por instalador en el Gantt general — design

## Contexto

El Gantt de la pantalla de inicio (`projects#index`) dibuja una barra por proyecto, coloreada hoy por la etapa actual del proyecto (`Project#current_stage&.stage_template&.color`). Tiene más sentido colorear ahí por **instalador asignado** — de un vistazo se ve qué instalador tiene qué proyectos — mientras que el Gantt del detalle de proyecto (una barra por *etapa*) sigue coloreando por `StageTemplate#color`, sin cambios, porque ahí las barras representan etapas, no instaladores.

`Installer` no tiene columna `color` todavía. Sigue exactamente el mismo patrón que `StageTemplate#color` (mismo tipo de columna, misma validación, mismo `color_field` en el form admin) — confirmado leyendo `db/migrate/20260723115556_add_color_to_stage_templates.rb` y `app/models/stage_template.rb`.

Nota de la ronda anterior, aplicada aquí desde el inicio: el bug de "el color no se guarda" que acabamos de arreglar fue porque `Admin::StageTemplatesController#stage_template_params` no permitía `:color` en strong params. Esta vez el plan incluye permitir `:color` en `Admin::InstallersController#installer_params` como parte del mismo commit que agrega la columna — no como un fix posterior.

## Alcance

1. **`Installer#color`** — columna nueva, misma forma que `StageTemplate#color` (hex, default gris `#6c757d`, validado).
2. **Admin::InstallersController** — permite `:color`; el form de instaladores agrega un `color_field`.
3. **`Project#installer`** — método nuevo que resuelve el instalador asignado al proyecto (o `nil` si todavía no se le asignó ninguno), sin asumir que la clave del campo dinámico se llama literalmente `"instalador"` — busca el `FieldDefinition` del propio `project_type` cuyo `reference_table` sea `"installers"`.
4. **Gantt general (`projects/index.html.erb`)** — colorea cada barra de proyecto por `project.installer&.color`, con el mismo gris `#6c757d` de fallback cuando no hay instalador asignado. Deja de usar `current_stage`/`stage_template` para el color (sigue usándose para nada más en esa vista — no había otro uso).
5. **Fix de especificidad CSS aplicado desde el inicio** — la regla de color para esta vista usa el mismo patrón `.gantt .bar-wrapper.X .bar, .gantt .bar-wrapper.X:hover .bar, .gantt .bar-wrapper.X.active .bar` que ya corregimos para el color por etapa, para no reintroducir el mismo bug con la nueva feature.

Fuera de alcance: cambiar el color del Gantt del detalle de proyecto (sigue por etapa), mostrar el instalador de alguna otra forma visual (ej. avatar, iniciales), permitir múltiples instaladores por proyecto.

## 1. `Installer#color`

Migración (mismo patrón que `add_color_to_stage_templates`):

```ruby
class AddColorToInstallers < ActiveRecord::Migration[7.2]
  def change
    add_column :installers, :color, :string, null: false, default: "#6c757d"
  end
end
```

`app/models/installer.rb`:

```ruby
class Installer < ApplicationRecord
  validates :name, presence: true
  validates :color, format: { with: /\A#[0-9a-fA-F]{6}\z/, message: "debe ser un color hexadecimal (ej. #6c757d)" }
end
```

## 2. Admin::InstallersController + form

`app/controllers/admin/installers_controller.rb` — cambia solo:

```ruby
  def installer_params
    params.require(:installer).permit(:name, :color)
  end
```

`app/views/admin/installers/_form.html.erb` agrega, después del campo `:name` (mismo bloque que ya existe en `admin/stage_templates/_form.html.erb`):

```erb
  <div class="mb-3">
    <%= form.label :color, class: "form-label" %>
    <%= form.color_field :color, class: "form-control form-control-color" %>
  </div>
```

## 3. `Project#installer`

`app/models/project.rb`, junto a los otros métodos públicos (`start_date`, `end_date`, `gantt_window`, `current_stage`):

```ruby
def installer
  key = project_type.field_definitions.find_by(reference_table: "installers")&.key
  return nil if key.nil?

  installer_id = custom_fields[key]
  return nil if installer_id.blank?

  Installer.find_by(id: installer_id)
end
```

(Devuelve `nil` en dos casos legítimos y uno defensivo: el tipo de proyecto no tiene ningún campo que referencie `installers` — poco probable pero posible en un `ProjectType` distinto a "Instalaciones"—; el proyecto todavía no tiene ese campo lleno (caso explícito que mencionaste — un proyecto recién creado puede no tener instalador asignado); o el `id` guardado ya no corresponde a ningún `Installer` existente (borrado después de asignarlo) — `find_by` devuelve `nil` en vez de lanzar `RecordNotFound`, a diferencia de `find`.)

## 4. Gantt general colorea por instalador

`app/views/projects/index.html.erb`, dentro del bloque que arma `gantt_tasks`/`gantt_colors`:

```erb
<%
  gantt_tasks = @projects.map do |project|
    first, last = project.gantt_window
    installer = project.installer
    progress_values = project.project_stages.map(&:progress_percent)
    average_progress = progress_values.any? ? (progress_values.sum / progress_values.size.to_f).round : 0
    {
      id: project.id.to_s,
      name: project.name,
      start: first.to_s,
      end: last.to_s,
      progress: average_progress,
      edit_url: project_path(project),
      custom_class: "installer-color-#{installer&.id || 'none'}"
    }
  end
  gantt_colors = @projects.map do |project|
    installer = project.installer
    [installer&.id || "none", installer&.color || "#6c757d"]
  end.uniq
%>
```

(`current_stage`/`stage_template` deja de calcularse en esta vista — no se usaba para nada más aquí. Sigue usándose sin cambios en `projects/show.html.erb`, que no se toca.)

## 5. CSS con la especificidad correcta desde el inicio

```erb
<style>
  <% gantt_colors.each do |installer_id, color| %>
    .gantt .bar-wrapper.installer-color-<%= installer_id %> .bar,
    .gantt .bar-wrapper.installer-color-<%= installer_id %>:hover .bar,
    .gantt .bar-wrapper.installer-color-<%= installer_id %>.active .bar {
      fill: <%= color %>;
    }
  <% end %>
</style>
```

## Testing

- Modelo: `Installer#color` — válido con hex de 6 dígitos, inválido sin `#`/con longitud incorrecta (mismo patrón que el test existente de `StageTemplate#color`).
- Modelo: `Project#installer` — con instalador asignado (devuelve el `Installer` correcto), sin ningún valor en `custom_fields` para ese campo (devuelve `nil` — el caso "proyecto recién creado, sin instalador todavía" que mencionaste), con un `id` que ya no existe en `installers` (devuelve `nil`, no lanza excepción).
- Controlador: `Admin::InstallersController#update` — guarda el color (mismo tipo de test que agregamos para `StageTemplate` tras encontrar el bug de strong params — se verifica explícitamente para no repetir el mismo error con `Installer`).
- Controlador: `projects#index` — el Gantt colorea la barra de un proyecto por el color de su instalador asignado; un proyecto sin instalador usa el gris `#6c757d` por defecto; la regla generada incluye las variantes `:hover`/`.active`.

## Edge cases

- Un proyecto de un `ProjectType` que no tiene ningún campo `reference_table: "installers"` (ej. un tipo de proyecto futuro sin ese concepto): `Project#installer` devuelve `nil`, la barra usa el gris por defecto — no rompe.
- Dos proyectos con el mismo instalador asignado: comparten la misma clase CSS (`installer-color-N`) y el mismo color — comportamiento esperado, ya cubierto por el `.uniq` en `gantt_colors`.
- Cambiar el color de un instalador después de que ya hay proyectos coloreados con el color anterior: se refleja al instante en el siguiente request (mismo razonamiento ya verificado para `StageTemplate#color` — sin caché de por medio).
