# Columna de responsables en la tabla "Listado"

## Contexto

`app/views/projects/_project_type_section.html.erb` (usada en `/projects/tipo/:slug`)
tiene una tabla "Listado" (líneas 236-282) con columnas Nombre/Estado/Avance,
pero no muestra a quién está asignado cada proyecto. El Gantt de la misma
página sí colorea sus barras por responsable, pero solo cuando hay un
"Tipo de responsable" elegido en el filtro de arriba (`section_params[:responsible_type_id]`,
ya resuelto en `selected_type` en la línea 102/122) — sin ese filtro, el Gantt
no tiene colores ni leyenda.

Los datos de responsables por proyecto ya se calculan hoy para el Gantt
(`gantt_tasks[:responsibles]`, línea 117):
`project.project_responsibles.includes(:responsible_type).map { |pr| { type: ..., name: ..., color: ... } }`
— sin filtrar por `project_wide?`. Para la nueva columna usamos el mismo
patrón pero solo con responsables **project-wide** (`project_stage_id.nil?`),
que es el mismo criterio que ya usa `Project#responsible_for` (el que
alimenta el color del Gantt) y la asignación masiva — así la columna nueva
muestra exactamente lo que la asignación masiva puede tocar, no asignaciones
puntuales de etapa.

## Cambio

### 1. Evitar N+1

`ProjectsController#build_section` (línea 289) hoy hace:
```ruby
Project.visible_to(current_user).where(project_type: project_type)
  .includes(:project_type, project_stages: :stage_template).order(:name)
```
Agregar `project_responsibles: :responsible_type` al `includes` para que
recorrer `page_projects` en la tabla no dispare una query por proyecto:
```ruby
.includes(:project_type, project_stages: :stage_template, project_responsibles: :responsible_type)
```

`gantt_tasks[:responsibles]` (línea 117) hoy hace
`project.project_responsibles.includes(:responsible_type)` — con el
`includes` de arriba puesto, esa llamada queda redundante y en los hechos
contraproducente: `.includes` sobre una asociación ya precargada devuelve
una relation NUEVA y dispara una query propia en vez de reusar lo
precargado, reintroduciendo el N+1 justo ahí. Se cambia esa línea a
`project.project_responsibles` a secas, para que sí use la precarga del
controller.

### 2. Columna nueva en la tabla

`app/views/projects/_project_type_section.html.erb`, entre "Estado" y "Avance":

Header (línea 243):
```erb
<th>Nombre</th><th>Estado</th><th>Responsables</th><th>Avance</th><th></th>
```

Por cada proyecto en el loop (después de la celda de Estado, línea 254),
computar y renderizar:
```erb
<td>
  <% project.project_responsibles.select(&:project_wide?).sort_by { |pr| pr.responsible_type_id == selected_type&.id ? 0 : 1 }.each do |pr| %>
    <div class="d-flex align-items-center gap-1<%= " fw-bold" if pr.responsible_type_id == selected_type&.id %>">
      <span class="rounded-circle d-inline-block" style="width: 0.65rem; height: 0.65rem; background-color: <%= pr.responsible_color %>;"></span>
      <small><%= pr.responsible_type.name %>: <%= pr.responsible_name %></small>
    </div>
  <% end %>
</td>
```
- `pr.responsible_color`/`pr.responsible_name` ya existen como columnas
  propias en `project_responsibles` (snapshot tomado al asignar, ver
  `ProjectResponsible#snapshot_responsible` en app/models/project_responsible.rb) —
  no hace falta ir a `pr.responsible.name`/`.color`, evita otra asociación.
- Sin responsables project-wide asignados, la celda queda vacía (ningún
  `<div>` se renderiza) — no se agrega un placeholder tipo "—".
- El responsable cuyo `responsible_type_id` coincide con `selected_type`
  (el filtro activo, mismo que colorea el Gantt) se ordena primero y se
  marca en negrita (`fw-bold`); el resto aparece debajo sin destacar. Si
  no hay filtro activo (`selected_type` nil), ningún responsable se
  destaca y el orden queda tal cual vino de la base (por
  `responsible_type_id`, sin ORDER explícito en la asociación — aceptable,
  no se pidió un orden particular para el caso sin filtro).

## Fuera de alcance

- No se tocan responsables asignados a una etapa puntual
  (`project_stage_id` no nil) — la columna es project-wide únicamente,
  igual que el Gantt y la asignación masiva.
- No se agrega un estilo de badge tipo "pill" nuevo — se reusa el mismo
  patrón de punto de color + texto chico que ya usa
  `app/views/projects/_gantt_legend.html.erb`, sin introducir un
  componente visual nuevo.
- No se cambia el criterio de qué proyectos aparecen en la tabla (eso ya
  lo maneja el filtro `responsible_id`/`responsible_type_id` existente en
  `build_section` — la columna nueva es solo de presentación).

## Testing

- Test de controlador: un proyecto con un responsable project-wide
  asignado (tipo Instalador) muestra su nombre en la celda de la tabla
  ("Instalador: Ana Gómez").
- Test: un responsable asignado a una etapa puntual (no project-wide) NO
  aparece en la columna.
- Test: con `responsible_type_id` filtrado, el responsable de ese tipo
  aparece con la clase `fw-bold`; otro responsable de un tipo distinto en
  el mismo proyecto aparece sin esa clase.
- Test: un proyecto sin responsables asignados no rompe el render (celda
  vacía, sin error).
- Verificar manualmente (o con un test de queries) que agregar el
  `includes` no reintroduce N+1 — comparar el conteo de queries antes/después
  con `assert_queries_count` o inspección visual del log de SQL para una
  página con varios proyectos.
