# Etapas no aplicables y etapas propias de un proyecto

**Fecha:** 2026-09-01
**Estado:** Aprobado, pendiente de plan de implementación

## Problema

Hoy `Project#build_stages_from_template` crea, al crear el proyecto, un
`ProjectStage` por cada `StageTemplate` del tipo de proyecto, y ese conjunto
queda fijo. En la práctica:

1. Algunos proyectos no pasan por todas las etapas estándar del tipo.
2. Algunos proyectos necesitan una etapa propia, que no está en la plantilla
   del tipo.

No hay forma hoy de reflejar ninguno de los dos casos sin ensuciar el Gantt,
el avance del proyecto o el filtro de "pendientes de fecha" con etapas que
no corresponden.

## Alcance

- `ProjectStage` (nueva columna, scope/filtrado).
- `Project` (métodos que iteran `project_stages`: avance, etapa actual,
  pendientes de fecha, cálculo automático de duración).
- Vista de detalle de proyecto: tabla de etapas, botón "+ Etapa", botón "No
  aplica" por fila, sección plegable de etapas no aplicables, Gantt.
- Un controller nuevo, acotado, solo para crear una etapa propia de un
  proyecto (`ProjectStagesController#create`).

Fuera de alcance: reordenar etapas dentro de un proyecto (se agregan al
final); editar el nombre de una etapa ya creada; permitir a usuarios
restringidos (solo avance) marcar/crear etapas.

## Modelo de datos

`project_stages.not_applicable` — boolean, `null: false`, default `false`.

`ProjectStage` gana:
```ruby
scope :applicable, -> { where(not_applicable: false) }
```
Usado solo en consultas frescas (no sobre una asociación ya precargada —
ver "Cuidado de performance" abajo).

Una etapa propia es simplemente un `ProjectStage` con `stage_template_id:
nil`, igual que una etapa cuyo template fue borrado — ya soportado a nivel
de modelo, sin cambios de esquema adicionales.

## Agregar una etapa propia

`accepts_nested_attributes_for :project_stages, update_only: true` en
`Project` bloquea deliberadamente crear etapas vía el form anidado
existente (evita que el form de edición de fechas/avance se use para
inyectar etapas). Para no tocar ese mecanismo, se agrega un controller
nuevo y mínimo:

```ruby
class ProjectStagesController < ApplicationController
  before_action :set_project
  before_action :authorize_edit!
  before_action :set_project_stage, only: [:update]

  def create
    @project_stage = @project.project_stages.new(project_stage_params)
    if @project_stage.save
      redirect_to project_path(@project)
    else
      redirect_to project_path(@project), alert: @project_stage.errors.full_messages.to_sentence
    end
  end

  def update
    @project_stage.update(project_stage_toggle_params)
    redirect_to project_path(@project)
  end
end
```

Ruta: `resources :project_stages, only: [:create, :update]` anidada bajo
`projects`. Permiso: mismo criterio que el resto de la gestión de etapas —
`current_user.can_edit_project?(@project)`.

UI (crear): botón "+ Etapa" (mismo patrón visual que "+ Evento") junto a la
tabla de etapas, abre un modal con nombre (requerido), fecha de inicio y
fecha de fin (opcionales, igual que hoy permite una etapa de plantilla).

## Marcar "No aplica" / reactivar

**Nota de diseño:** la tabla de etapas (`_stage_table.html.erb`) ya está
íntegramente envuelta en un `<form>` (el de "Guardar cambios", que edita
fechas/avance en bloque). Un botón "No aplica" con su propio mini-form
anidado ahí adentro sería HTML inválido (`<form>` dentro de `<form>`). En
vez de reutilizar el patrón del botón "Archivar" (que si es un mini-form
independiente, pero fuera de cualquier otro form), se usa `link_to` con
`data: { turbo_method: :patch }` contra el `update` del controller nuevo
— la app ya depende de `turbo-rails`, y un `<a>` no tiene el problema de
anidamiento de un `<form>`.

- En la tabla de etapas normal (`_stage_table.html.erb`), cada fila
  aplicable tiene un botón "No aplica" que pega `not_applicable: true`
  para esa etapa.
- Al final de esa tabla, si hay etapas no aplicables, una sección plegable
  nativa (`<details><summary>Etapas no aplicables (N)</summary>...`, sin
  JS) las lista con un botón "Reactivar" (`not_applicable: false`).
- `_stage_table_restricted.html.erb` (usuarios que solo cargan avance)
  solo filtra las no aplicables de su listado — no gana botones nuevos,
  ya que marcar/crear etapas es una decisión de gestión del proyecto, no
  de carga de avance.

## Dónde se excluyen las etapas no aplicables

- **Gantt** (`show.html.erb`): la consulta de `stages` para construir
  `gantt_tasks` filtra `not_applicable: false` en SQL (consulta fresca,
  sin asociación precargada de por medio).
- **`Project#progress_percent` / `#progress_status`**: excluyen las no
  aplicables antes de promediar/evaluar.
- **`Project#current_stage`**: excluye las no aplicables antes de elegir
  cuál es la etapa "actual" (usada para elegir el responsable
  representativo del proyecto).
- **`Project#stages_missing_dates`**: excluye las no aplicables, para que
  no aparezcan en el panel de "Pendientes de fecha".
- **`Project#pending_auto_duration_start_date?`**: si la primera etapa de
  la plantilla resulta no aplicable en este proyecto, no debe bloquear el
  cálculo automático de duración.
- **`Project#apply_auto_duration!`**: salta las etapas no aplicables al
  asignar fechas calculadas.
- **`Project#start_date` / `#end_date`** (y por lo tanto `#gantt_window` y
  `#overdue?`, que dependen de ellos): excluyen las no aplicables antes de
  calcular el mínimo/máximo. Esto es lo que alimenta el **Gantt general**
  (`_project_type_section.html.erb`, una barra por proyecto en el listado
  por tipo) — si una etapa no aplicable queda con fechas cargadas de antes
  de marcarla, hoy seguiría estirando el rango de la barra del proyecto en
  ese Gantt; sin esta exclusión el fix quedaría incompleto justo en la
  vista más usada.
- **Filtro por etapa específica en el Gantt general**
  (`_project_type_section.html.erb`, cuando `section[:stage_name]` está
  presente): si la etapa buscada por nombre existe pero está marcada no
  aplicable para ese proyecto, se trata igual que si no existiera (el
  proyecto se omite de ese Gantt filtrado), en vez de mostrar una barra
  con la ventana de una etapa que el proyecto marcó como no aplicable.

## Cuidado de performance

Los métodos de `Project` de la lista anterior (excepto el Gantt, que ya
hace su propia consulta) operan sobre la asociación `project_stages`, que
en varias vistas (listado, tracker) ya viene precargada con `.includes`
para evitar N+1. Ahí se filtra en Ruby (`.reject(&:not_applicable?)`
sobre la asociación ya cargada), nunca con el scope `.applicable` (que al
ser un `where` dispararía una consulta nueva y perdería el precargado).
`.applicable` se reserva para consultas que de todos modos van a pegarle
fresco a la base (la tabla de etapas del proyecto, el Gantt, el controller
nuevo).

## Fuera de alcance (explícito)

- Reordenar etapas dentro de un proyecto.
- Editar el nombre/plantilla de una etapa ya creada.
- Que usuarios con acceso restringido (solo avance) puedan marcar
  "No aplica" o crear etapas propias.
