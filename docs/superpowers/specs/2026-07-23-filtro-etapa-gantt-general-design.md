# Filtro por etapa en el Gantt general — design

## Contexto

El Gantt general de `projects#index` muestra una barra por proyecto con su rango completo (`Project#gantt_window`: desde el inicio de su primer subproceso hasta el fin del último). Se quiere poder elegir una etapa específica (ej. "Instalación") y ver, para cada proyecto, únicamente el tramo de esa etapa — útil para ver qué proyectos están en una fase determinada en un rango de tiempo dado.

## Alcance

Un nuevo desplegable "Etapa" en la tarjeta de filtros existente de `projects#index`, con las etapas configuradas (`StageTemplate.name`, distintas entre todos los tipos de proyecto). Es un cambio puro de **vista**: no modifica la consulta de `@projects` ni afecta la tabla "Listado" ni las tarjetas KPI (Total/Vencidos/Finalizados), que siguen mostrando el conjunto completo determinado por los demás filtros. Solo cambia cómo se arma `gantt_tasks`.

Fuera de alcance: filtrar la tabla Listado por etapa (confirmado explícitamente — es exclusivo del Gantt). Cambiar el color de las barras (se mantiene por instalador, sin cambios). `projects#tracker` (Seguimiento) no se toca.

## Diseño

`app/controllers/projects_controller.rb`, en `index`, agregar junto a las demás variables de la vista:

```ruby
    @stage_names = StageTemplate.distinct.order(:name).pluck(:name)
```

(No requiere ningún filtrado adicional sobre `@projects` — es solo para poblar el desplegable.)

Vista — nuevo campo en el formulario de filtros existente (`app/views/projects/index.html.erb`), antes del campo "Buscar":

```erb
      <div class="col-auto">
        <%= form.label :stage_name, "Etapa", class: "form-label" %>
        <%= form.select :stage_name, @stage_names,
              { include_blank: "Todas" }, class: "form-select" %>
      </div>
```

Al construir `gantt_tasks`, si `params[:stage_name]` está presente, cada proyecto usa las fechas de su propio `project_stage` con ese nombre (en vez del rango completo), con el mismo respaldo de fechas por defecto que ya usa el Gantt de detalle (`show.html.erb`) cuando un subproceso no tiene fechas cargadas. Si el proyecto no tiene ningún `project_stage` con ese nombre, se excluye del Gantt (no genera una entrada en `gantt_tasks`), pero sigue apareciendo en la tabla:

```erb
  <%
    gantt_tasks = projects_list.filter_map do |project|
      if params[:stage_name].present?
        stage = project.project_stages.find { |s| s.name == params[:stage_name] }
        next if stage.nil?
        stage_start = stage.start_date || project.created_at.to_date
        stage_end = stage.end_date || (stage_start + 7.days)
        first, last = stage_start, stage_end
      else
        first, last = project.gantt_window
      end
      progress_values = project.project_stages.map(&:progress_percent)
      average_progress = progress_values.any? ? (progress_values.sum / progress_values.size.to_f).round : 0
      {
        id: project.id.to_s,
        name: project.name,
        start: first.to_s,
        end: last.to_s,
        progress: average_progress,
        edit_url: project_path(project),
        custom_class: "installer-color-#{project.installer&.id || 'none'}"
      }
    end
  %>
```

`Array#filter_map` reemplaza al `.map` actual: descarta (`next`, equivalente a `nil`) los proyectos sin esa etapa cuando el filtro está activo, y construye el hash normalmente en cualquier otro caso. `gantt_colors` sigue derivándose de `projects_list` completo (no de `gantt_tasks`), así que no necesita cambios — sigue coloreando por instalador para todos los proyectos, tengan o no barra visible en el Gantt filtrado.

## Testing

- Controlador: `index` con `stage_name` — el proyecto que tiene esa etapa aparece en `gantt-tasks` con las fechas de esa etapa específica (no el rango completo del proyecto).
- Controlador: `index` con `stage_name` — un proyecto sin esa etapa (de otro tipo de proyecto) no aparece en `gantt-tasks`, pero sigue en la tabla Listado.
- Controlador: `index` sin `stage_name` — se comporta igual que antes (rango completo por proyecto).
- Vista: el desplegable "Etapa" muestra las opciones distintas de `StageTemplate.name`.

## Edge cases

- Proyecto cuya etapa filtrada no tiene fechas cargadas (`start_date`/`end_date` nulos): usa el mismo respaldo de "una semana desde la creación del proyecto" que ya usa el Gantt de detalle, en vez de romper o mostrar fechas `nil`.
- Ningún proyecto tiene la etapa elegida: `gantt_tasks` queda vacío (`[]`), el script ya maneja ese caso (`if tasks.length > 0`) sin renderizar el Gantt — comportamiento existente, sin cambios necesarios.
- Dos tipos de proyecto con una etapa de mismo nombre pero fechas independientes: cada proyecto usa su propio `project_stage` (coincidencia por nombre, no por `stage_template_id`), así que funciona correctamente incluso si en el futuro hay más de un tipo de proyecto.
