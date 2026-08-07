# El badge del navbar debe contar también los tipos con duración automática

## Contexto

`ApplicationHelper#pending_stage_dates_count(user)` (app/helpers/application_helper.rb:37-45)
alimenta el badge junto al link "Proyectos" en la navbar
(`app/views/layouts/_navbar.html.erb:7-10`). Su query SQL solo filtra
`project_types: { require_stage_dates: true }` — el mismo gap que ya se
corrigió hoy en el panel "Pendientes de fecha" y en las tres omisiones del
Gantt, que ya usan `require_stage_dates? || auto_stage_duration_enabled?`.

Resultado: un tipo de proyecto con solo `auto_stage_duration_enabled`
activo lista correctamente sus proyectos pendientes en el panel de esa
página, pero el badge global de la navbar no los suma — dos contadores
del mismo concepto que no coinciden.

## Cambio

En `pending_stage_dates_count`, ampliar el `.where(project_types: {
require_stage_dates: true })` a ambos flags con SQL crudo (es una
condición OR entre dos columnas de la misma tabla, no se puede expresar
con el hash shorthand de ActiveRecord):

```ruby
.where("project_types.require_stage_dates = TRUE OR project_types.auto_stage_duration_enabled = TRUE")
```

El resto de la query (visibilidad por usuario, excluir archivados, "alguna
etapa sin `start_date`/`end_date`") no cambia — es el mismo criterio de
"etapa sin fecha" que ya usa el panel, solo se amplía a qué tipos de
proyecto cuentan.

## Fuera de alcance

No se toca el panel de pendientes ni las omisiones del Gantt (ya
corregidos hoy) — solo esta query.

## Testing

Actualizar los tests existentes de `pending_stage_dates_count`
(`test/helpers/application_helper_test.rb`) que hoy codifican el
comportamiento "solo cuenta `require_stage_dates`" en su nombre y
contenido, y agregar un test nuevo: un tipo con solo
`auto_stage_duration_enabled` activo y un proyecto sin fecha en alguna
etapa debe sumar al contador.
