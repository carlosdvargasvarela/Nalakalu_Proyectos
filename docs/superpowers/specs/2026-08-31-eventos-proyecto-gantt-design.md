# Eventos de proyecto en el Gantt

**Fecha:** 2026-08-31
**Estado:** Aprobado, pendiente de plan de implementación

## Problema

Los proyectos necesitan poder registrar eventos puntuales (reuniones, hitos,
entregas, etc.) asociados opcionalmente a un subproceso (`ProjectStage`), y
que esos eventos se vean como puntos sobre el Gantt del proyecto, además de
en un listado.

## Alcance

Aplica solo al Gantt de detalle de proyecto (`projects/show.html.erb`, una
barra por `ProjectStage`). El Gantt de listado por tipo de proyecto
(`_project_type_section.html.erb`, una barra por proyecto) queda fuera de
alcance: ahí no hay una etapa individual visible por fila, así que el mismo
patrón de superposición no aplica.

## Modelo de datos

### `event_types`

Configurables por admin, por `ProjectType` — mismo patrón que `stage_templates`.

| columna | tipo | notas |
|---|---|---|
| `project_type_id` | bigint, null: false | FK |
| `name` | string, null: false | |
| `color` | string, null: false, default `"#6c757d"` | hex, mismo formato/validación que `stage_templates.color` |
| `icon` | string | reutiliza el icon picker ya existente en `project_types.icon` |
| `position` | integer, default 0 | orden en selects/admin |

### `events`

| columna | tipo | notas |
|---|---|---|
| `project_id` | bigint, null: false | FK |
| `project_stage_id` | bigint, opcional | si presente, el evento se dibuja sobre la barra de esa etapa; si no, va en la fila "Eventos del proyecto" |
| `event_type_id` | bigint, null: false | define color/ícono del marcador |
| `title` | string, null: false | |
| `event_date` | date, null: false | |
| `event_time` | time, opcional | |
| `responsible_id` | bigint, opcional | FK directa a `Responsible` (sin `responsible_type_id`, a diferencia de `ProjectResponsible`) |
| `notes` | text, opcional | |
| `status` | string, opcional, default `"pendiente"` | `"pendiente"` / `"realizado"` |

Validaciones:
- `title`, `event_date`, `event_type` presentes.
- `project_stage`, si está presente, debe pertenecer a `project` (mismo patrón que `ProjectResponsible#project_stage_belongs_to_project`).
- `event_type` debe pertenecer al `project_type` de `project` (mismo patrón que `ProjectResponsible#responsible_type_belongs_to_project_type`).

## Administración

Bajo `Admin::ProjectTypes`, junto a la sección de "Subprocesos"
(`stage_templates`), se agrega una sección "Tipos de evento" con CRUD
idéntico al de `stage_templates`: nombre, color, ícono, orden.

## CRUD de eventos

Desde `projects/show.html.erb`, un botón "+ Evento" abre un modal (mismo
patrón que el modal de asignación masiva ya existente) con: tipo de evento,
título, fecha, hora (opcional), etapa (select "Todo el proyecto" + etapas
del proyecto, igual al select ya usado para `project_stage_id` en
responsables), responsable (opcional, select de `Responsible`s del
proyecto), notas, estado.

Permisos: los mismos que hoy permiten editar etapas —
`current_user.can_edit_project?(project)`.

## Render en el Gantt

`frappe-gantt` no soporta nativamente superponer un marcador sobre una
barra existente — solo dibuja una fila (barra) por tarea. Se logra el
efecto pedido extendiendo `gantt_stage_editor_controller.js` (que ya
manipula el SVG renderizado por frappe-gantt, ej. `applyBarColors`):

- Después del render de frappe-gantt, por cada evento con `project_stage_id`
  presente: calcular la posición X a partir de `event_date` con la misma
  fórmula que usa frappe-gantt internamente (offset en días desde el inicio
  del gantt × ancho de columna actual), y dibujar un marcador SVG (rombo)
  superpuesto en el eje Y de la barra de esa etapa, coloreado con
  `event_type.color`.
- Eventos sin `project_stage_id`: se agregan como tareas adicionales de tipo
  `milestone` de frappe-gantt (rombo nativo) en una fila extra "Eventos del
  proyecto" al final del gantt.
- Cada marcador es clickeable: abre un popover (Bootstrap, ya disponible en
  el proyecto) con título, fecha, tipo, responsable y notas, con enlace para
  editar el evento (abre el modal de edición).
- El recálculo de posiciones debe repetirse en los mismos hooks donde hoy se
  reaplican colores de barra (cambio de modo de vista Día/Semana/Mes,
  reorder, etc.), ya que cambia el ancho de columna.

## Listado de eventos

Debajo del Gantt, en `projects/show.html.erb`, una tabla simple con todos
los eventos del proyecto ordenados por fecha, con acciones de editar y
eliminar. Sirve como respaldo del Gantt para consulta rápida o en pantallas
chicas.

## Fuera de alcance

- Eventos en el Gantt de listado por tipo de proyecto
  (`_project_type_section.html.erb`).
- Notificaciones/recordatorios de eventos próximos.
- Recurrencia de eventos.
