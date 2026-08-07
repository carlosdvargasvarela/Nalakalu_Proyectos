# Panel "Pendientes de fecha" debe respetar el filtro de etapa

## Contexto

`app/views/projects/_project_type_section.html.erb` tiene un filtro "Etapa"
(`section[:stage_name]`) que ya se usa para acotar el Gantt a una sola etapa
por proyecto (líneas 88-99: si hay filtro, cada barra usa solo la fecha de
esa etapa puntual).

El panel "Pendientes de fecha" (líneas 130-161) ignora ese filtro por
completo: siempre usa `project.stages_missing_dates` (cualquier etapa sin
fecha) y `project.pending_auto_duration_start_date?` (si la primera etapa
por posición no tiene fecha), sin importar qué etapa esté seleccionada en
el filtro "Etapa". Resultado: si filtrás por "Instalación" y un proyecto
tiene "Instalación" con fecha pero "Diseño-Aprobación" sin fecha, el
proyecto igual aparece en el panel — mezclando el estado de una etapa que
no es la que estás mirando.

## Objetivo

Cuando el filtro "Etapa" está activo, el panel de pendientes se acota a esa
etapa puntual: un proyecto aparece solo si **esa** etapa filtrada no tiene
fecha, sin importar el estado de las demás etapas. Sin filtro activo, el
panel se comporta exactamente igual que hoy (cualquier etapa sin fecha, o
falta la fecha de inicio para el cálculo automático).

## Comportamiento

En el `filter_map` que arma `pending_projects`:

- **Con filtro de etapa activo** (`section[:stage_name].present?`): buscar
  la etapa de ese proyecto con ese nombre (mismo `find` que ya usa el
  bloque del Gantt un poco más arriba). Si el proyecto no tiene esa etapa,
  se excluye. Si la tiene y le falta fecha (`dates_missing?`), aparece en
  el panel mostrando solo esa etapa como la que falta. Si la etapa ya
  tiene fecha, el proyecto no aparece en el panel — sin importar si otras
  etapas del mismo proyecto están sin fecha.
- **Sin filtro** (comportamiento actual, sin cambios): aparece si tiene
  alguna etapa sin fecha (`stages_missing_dates`) o si le falta la fecha de
  inicio para el cálculo automático (`pending_auto_duration_start_date?`).

El botón "Calcular" (para tipos con cálculo automático) sigue apareciendo
según `pending_auto_duration_start_date?` en ambos casos — es una acción
sobre el proyecto entero (recalcula desde la primera etapa), no depende de
cuál etapa estés filtrando.

## Fuera de alcance

No se toca el Gantt ni el resto de los filtros — solo la construcción de
`pending_projects` dentro del bloque ya existente.

## Testing

Test de controlador: con el filtro de etapa activo, un proyecto con esa
etapa puntual sin fecha aparece en el panel aunque otras etapas sí tengan
fecha; un proyecto con esa etapa puntual con fecha NO aparece aunque otras
etapas no tengan fecha. Sin filtro, el comportamiento actual (ya cubierto
por tests existentes) no debe romperse.
