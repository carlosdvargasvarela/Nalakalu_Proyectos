# El Gantt debe omitir etapas sin fecha también para tipos con cálculo automático

## Contexto

Dos vistas Gantt deciden si mostrar el placeholder de 7 días para una etapa
sin fecha mirando **solo** `project_type.require_stage_dates?`:

- `app/views/projects/_project_type_section.html.erb`, dos condiciones de
  omisión (líneas 92 y 97):
  ```erb
  next if project_type.require_stage_dates? && stage.dates_missing?          # filtrado por etapa
  next if project_type.require_stage_dates? && project.project_stages.all?(&:dates_missing?)  # sin filtro
  ```
- `app/views/projects/show.html.erb` (línea 34): `require_dates = @project.project_type.require_stage_dates?`,
  usado en la línea 35 para decidir si filtrar `stages` con `reject(&:dates_missing?)`.

El panel "Pendientes de fecha" (en `_project_type_section.html.erb`, línea
130) en cambio ya se muestra para `require_stage_dates? ||
auto_stage_duration_enabled?` — dos flags independientes, cada uno
introducido en una feature distinta (`require-stage-dates` y
`auto-stage-duration`).

Resultado observado: un tipo de proyecto con `auto_stage_duration_enabled`
activo (pero `require_stage_dates` apagado) lista correctamente sus
proyectos sin fecha en "Pendientes de fecha", pero el Gantt (tanto el de
listado como el del proyecto individual) igual dibuja una barra con el
placeholder de 7 días (`created_at` + 7 días) para esa etapa — el mismo
proyecto/etapa aparece como "pendiente" y como si ya tuviera fecha, al
mismo tiempo.

## Objetivo

Las tres condiciones de omisión (dos en `_project_type_section.html.erb`,
una en `show.html.erb`) deben usar el mismo criterio que ya usa el panel de
pendientes: `require_stage_dates? || auto_stage_duration_enabled?`. Un
proyecto/etapa que aparece en "Pendientes de fecha" nunca debe mostrar
simultáneamente una barra placeholder en ningún Gantt.

## Cambio

En las tres líneas, reemplazar `project_type.require_stage_dates?` por
`(project_type.require_stage_dates? || project_type.auto_stage_duration_enabled?)`.
Sin cambios en ningún otro archivo.

## Fuera de alcance

No se toca el panel de pendientes (ya usa el criterio correcto) ni la
lógica de cálculo de fechas.

## Testing

Tests de controlador para ambos Gantt (listado con/sin filtro de etapa, y
proyecto individual): con un tipo que tiene `auto_stage_duration_enabled`
activo (y `require_stage_dates` apagado), un proyecto/etapa sin fecha se
omite del Gantt — mismo patrón que los tests ya existentes para
`require_stage_dates`.
