# Tipo de responsable por defecto en el filtro — Design

## Contexto

`StageTemplate` ya tiene un patrón de "valor por defecto en el filtro": una columna `default_in_filter` (boolean), un checkbox en el form de admin, y un callback `before_save` que se asegura de que solo un `StageTemplate` por `ProjectType` tenga el flag activo. `ProjectsController#build_section` usa ese default para precargar `stage_name` en el filtro de `/projects` cuando el usuario todavía no filtró nada:

```ruby
filtered = params.key?(:status)
stage_name = if filtered
  params[:stage_name]
else
  project_type.stage_templates.find_by(default_in_filter: true)&.name
end
```

**Objetivo:** el mismo mecanismo para `ResponsibleType`, aplicado al filtro `responsible_type_id` en `/projects` (`build_section`) y en `/projects/tracker` (`tracker`).

## Arquitectura

### 1. Modelo

Columna nueva `default_in_filter` (`boolean`, `default: false`, `null: false`) en `responsible_types`, igual que en `stage_templates`. `ResponsibleType` gana el mismo callback que `StageTemplate`:

```ruby
before_save :clear_other_defaults, if: :default_in_filter?

private

def clear_other_defaults
  project_type.responsible_types.where.not(id: id).update_all(default_in_filter: false)
end
```

### 2. Admin

`app/views/admin/responsible_types/_form.html.erb` gana el mismo checkbox que `stage_templates/_form.html.erb`:

```erb
<div class="mb-3 form-check">
  <%= f.check_box :default_in_filter, class: "form-check-input" %>
  <%= f.label :default_in_filter, "Tipo de responsable por defecto en el filtro", class: "form-check-label" %>
</div>
```

`Admin::ResponsibleTypesController#responsible_type_params` permite `:default_in_filter`.

### 3. Runtime — `/projects` (`ProjectsController#build_section`)

Reusa la señal `filtered` que ya gatea `stage_name`. Cuando no hay filtro aplicado, `responsible_type_id` se precarga con el default; una vez que el usuario envía el form (aunque dejó "Todos"), se respeta su elección:

```ruby
def build_section(project_type)
  filtered = params.key?(:status)
  responsible_type_id = if filtered
    params[:responsible_type_id]
  else
    params[:responsible_type_id].presence || project_type.responsible_types.find_by(default_in_filter: true)&.id&.to_s
  end

  projects = Project.visible_to(current_user).where(project_type: project_type).includes(:project_type, project_stages: :stage_template).order(:name)
  projects = params[:status].present? ? projects.where(status: params[:status]) : projects.where.not(status: "archived")
  projects = filter_by_responsible(projects, responsible_type_id, params[:responsible_id])
  # ... resto sin cambios, usando responsible_type_id en vez de params[:responsible_type_id] donde corresponda (ej. el hash `params:` que se pasa a la vista)
```

El hash `params: params.slice(...)` que se le pasa a la vista para pre-seleccionar el `<select>` y armar los links de paginación también debe reflejar `responsible_type_id` (no el `params[:responsible_type_id]` crudo), para que el `<select>` del filtro se vea con el default ya elegido, no en blanco.

### 4. Runtime — `/projects/tracker` (`ProjectsController#tracker`)

El tracker no tiene una señal "recién llegado sin filtrar" existente (no usa `status`). Se usa `params.key?(:responsible_type_id)`: si el parámetro no vino en la URL (primera visita / link directo sin querystring), se aplica el default; si vino — aunque sea vacío ("Todos") — se respeta la elección del usuario.

```ruby
def tracker
  @project_types = ProjectType.all
  @project_type = ProjectType.find_by(id: params[:project_type_id]) || ProjectType.first
  @responsible_types = @project_type ? @project_type.responsible_types : ResponsibleType.none
  @responsible_type_id = if params.key?(:responsible_type_id)
    params[:responsible_type_id]
  else
    @project_type&.responsible_types&.find_by(default_in_filter: true)&.id&.to_s
  end
  @projects = if @project_type
    scope = Project.visible_to(current_user).where(project_type: @project_type).where.not(status: "archived")
                   .includes(project_stages: :stage_template).order(:name)
    filter_by_responsible(scope, @responsible_type_id, params[:responsible_id])
  else
    Project.none
  end
end
```

`app/views/projects/tracker.html.erb` cambia su `<select>`'s `selected:` de `params[:responsible_type_id]` a `@responsible_type_id`.

### 5. Locale

Ninguna nueva — `default_in_filter` no se traduce vía `activerecord.attributes` hoy para `stage_template` (el label del checkbox está hardcodeado en la vista, siguiendo el patrón existente), así que `responsible_type` tampoco lo necesita.

## Manejo de errores

- Si ningún `ResponsibleType` del `project_type` tiene `default_in_filter: true`, `find_by` devuelve `nil` y el filtro queda "Todos" — comportamiento actual sin cambios.
- Cambiar de tipo de proyecto (en el tracker, vía `project_type_id`) sin pasar `responsible_type_id` vuelve a aplicar el default del nuevo tipo — comportamiento esperado, coherente con cómo cambiar de tipo ya resetea `@responsible_types`.

## Testing

- **Modelo:** solo un `ResponsibleType` por `project_type` puede tener `default_in_filter: true` (test análogo al de `StageTemplate`); default es `false`.
- **Admin controller:** crear/actualizar con `default_in_filter` presente y ausente.
- **`ProjectsController#index`/`build_section`:** sin params → usa el default; con `status` presente y `responsible_type_id` vacío → respeta "Todos" (no fuerza el default); con `responsible_type_id` explícito → lo respeta.
- **`ProjectsController#tracker`:** sin `responsible_type_id` en la URL → usa el default; con `responsible_type_id=""` en la URL → respeta "Todos".

## Resumen de archivos

- Migración: `db/migrate/<timestamp>_add_default_in_filter_to_responsible_types.rb`
- Modificar: `app/models/responsible_type.rb`
- Modificar: `app/controllers/admin/responsible_types_controller.rb`
- Modificar: `app/views/admin/responsible_types/_form.html.erb`
- Modificar: `app/controllers/projects_controller.rb` (`build_section`, `tracker`)
- Modificar: `app/views/projects/tracker.html.erb`
- Test: `test/models/responsible_type_test.rb`
- Test: `test/controllers/admin/responsible_types_controller_test.rb`
- Test: `test/controllers/projects_controller_test.rb`
