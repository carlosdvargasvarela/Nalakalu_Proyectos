# Etapa por defecto + botón "Quitar filtros" — design

## Contexto

En `/projects`, cada sección (por tipo de proyecto) tiene un filtro de Etapa que hoy siempre arranca en "Todas". Se quiere poder configurar, por Subproceso (`StageTemplate`), cuál etapa debe venir preseleccionada la primera vez que se entra a esa sección. También se quiere un botón "Quitar filtros" por sección, para volver rápido a la vista sin ningún filtro aplicado.

## Alcance

1. **Etapa por defecto** — nueva columna `default_in_filter` (boolean) en `stage_templates`, editable vía checkbox en la pantalla de administración de Subprocesos. Al marcarlo, se desmarca automáticamente cualquier otro subproceso del mismo tipo (solo puede haber un default por tipo). En `/projects`, si una sección nunca fue filtrada (primera carga, sin ningún parámetro `sections[<slug>]` en la URL), el filtro de Etapa toma esa etapa por defecto en lugar de "Todas".
2. **Botón "Quitar filtros"** — un link junto al botón "Filtrar" de cada sección que resetea explícitamente todos sus campos (Estado, Instalador, Etapa, Desde/Hasta, Buscar, página) a vacío. Vuelve literalmente a "Todas" — no reaplica la etapa por defecto (confirmado explícitamente).

Fuera de alcance: `projects#tracker` (Seguimiento) no se toca. No se agrega ninguna dependencia nueva.

## 1. Etapa por defecto

### Migración

`db/migrate/YYYYMMDDHHMMSS_add_default_in_filter_to_stage_templates.rb`:

```ruby
class AddDefaultInFilterToStageTemplates < ActiveRecord::Migration[7.2]
  def change
    add_column :stage_templates, :default_in_filter, :boolean, default: false, null: false
  end
end
```

### Modelo

`app/models/stage_template.rb` — agregar un callback que desmarca cualquier otro subproceso del mismo tipo cuando este se marca como default:

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

### Admin — permitir el nuevo parámetro y mostrar el checkbox

`app/controllers/admin/stage_templates_controller.rb`, el `stage_template_params` privado:

```ruby
  def stage_template_params
    params.require(:stage_template).permit(:name, :position, :color, :default_in_filter)
  end
```

`app/views/admin/stage_templates/_form.html.erb`, agregar el checkbox antes del submit:

```erb
  <div class="mb-3 form-check">
    <%= form.check_box :default_in_filter, class: "form-check-input" %>
    <%= form.label :default_in_filter, "Etapa por defecto en el filtro", class: "form-check-label" %>
  </div>
```

### `/projects` — usar la etapa por defecto en la primera carga

`app/controllers/projects_controller.rb`, en `build_section`, distinguir "nunca se filtró esta sección" (no existe `params[:sections][<slug>]` en absoluto) de "se filtró y el campo Etapa quedó en blanco" (el hash existe, aunque `stage_name` esté vacío):

```ruby
  def build_section(project_type)
    section_params = params.dig(:sections, project_type.slug) || {}
    stage_name = if params.dig(:sections, project_type.slug).nil?
      project_type.stage_templates.find_by(default_in_filter: true)&.name
    else
      section_params[:stage_name]
    end
    # ... el resto de build_section usa `stage_name` en vez de `section_params[:stage_name]`
    # tanto para el cálculo de gantt_tasks (que se mueve a la vista, así que hay que
    # pasar `stage_name` en el hash de la sección) como para no perder el valor.
```

Como el cálculo de `gantt_tasks` vive en la vista (`_project_type_section.html.erb`), `stage_name` (ya resuelto con el fallback al default) se agrega al hash de la sección para que la vista lo use en vez de `section_params[:stage_name]` directamente:

```ruby
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
```

En `_project_type_section.html.erb`:
- El `<select>` de Etapa debe mostrar `selected: section[:stage_name]` (no `section_params[:stage_name]`), para que la opción por defecto aparezca marcada visualmente en la primera carga.
- El cálculo de `gantt_tasks` debe usar `section[:stage_name]` (no `section_params[:stage_name]`) para decidir si filtra por etapa.

## 2. Botón "Quitar filtros"

Un link junto al botón "Filtrar", que manda explícitamente todos los campos vacíos para esa sección — así el controlador ve que `params[:sections][<slug>]` **sí existe** (como hash, con valores en blanco) y no reaplica la etapa por defecto:

```erb
      <div class="col-auto align-self-end">
        <%= form.submit "Filtrar", class: "btn btn-primary" %>
        <%= link_to "Quitar filtros",
              projects_path(request.query_parameters.deep_merge(
                "sections" => { slug => { "status" => "", "installer_id" => "", "from_date" => "", "to_date" => "", "stage_name" => "", "q" => "", "page" => "" } }
              )),
              class: "btn btn-outline-secondary" %>
      </div>
```

## Testing

- Modelo: marcar `default_in_filter: true` en un subproceso desmarca cualquier otro default previo del mismo tipo.
- Admin: el checkbox "Etapa por defecto" se guarda correctamente al crear/editar un subproceso.
- Controlador: `/projects` sin ningún parámetro de sección — el filtro de Etapa de esa sección usa la etapa marcada como default.
- Controlador: `/projects` con `sections[<slug>][stage_name]` explícitamente vacío — no aplica ningún filtro de etapa (no reaplica el default).
- Vista: el botón "Quitar filtros" genera un link cuyos parámetros de sección quedan todos vacíos.
- Controlador: sin ningún subproceso marcado como default, el comportamiento es igual al actual (sin filtro de etapa en la primera carga).

## Edge cases

- Ningún subproceso marcado como default para un tipo: `find_by(default_in_filter: true)` devuelve `nil`, el filtro de Etapa se comporta exactamente como hoy (sin preselección).
- Dos requests simultáneos marcando defaults distintos del mismo tipo: el último `save` en completarse gana (comportamiento estándar de `update_all`, no es un caso que necesite manejo especial en una app de un solo usuario administrador a la vez).
- El botón "Quitar filtros" en una sección no afecta los filtros de las demás secciones (mismo mecanismo `deep_merge` ya usado por la paginación).
