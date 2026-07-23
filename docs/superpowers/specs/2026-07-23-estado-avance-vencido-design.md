# Estado de avance (Sin iniciar/Iniciado/Finalizado) y "Vencido" — design

## Contexto

Hoy `Project#status` solo distingue "activo"/"archivado" (ciclo de vida administrativo) y `ProjectStage#progress_percent` es un número crudo sin clasificación visual. El usuario pide un segundo eje de estado, basado en avance, tanto para el proyecto completo como para cada subproceso, más una señal independiente de "vencido" cuando la fecha de fin ya pasó y no está al 100%.

## Alcance

1. **`ProjectStage#progress_status`** — `"sin_iniciar"` (0%), `"iniciado"` (1-99%), `"finalizado"` (100%).
2. **`Project#progress_status`** — agregado sobre sus etapas: `"sin_iniciar"` si todas están en 0%, `"finalizado"` si todas están en 100%, `"iniciado"` en cualquier otro caso.
3. **`ProjectStage#overdue?`** / **`Project#overdue?`** — `true` solo si hay `end_date` **y** ya pasó **y** no está finalizado (100%). Sin fecha de fin asignada, nunca es vencido — no se puede estar atrasado respecto a una fecha que no existe.
4. **Badges nuevos**, mostrados juntos con los ya existentes (no los reemplazan): en el encabezado del detalle de proyecto, en la franja de cada proyecto en Seguimiento, y en cada fila de la tabla de etapas (compartida entre ambas vistas).

Fuera de alcance: tocar el color de las barras del Gantt (ya resuelto por instalador/etapa en rondas previas — agregar un tercer criterio de color competiría visualmente), mostrar estos badges en la pantalla de inicio (`projects#index`, no fue pedido — esa vista ya tiene su propio estado activo/archivado y su Gantt agregado).

## 1 y 3. `ProjectStage`

```ruby
def progress_status
  return "finalizado" if progress_percent == 100
  return "sin_iniciar" if progress_percent.zero?
  "iniciado"
end

def overdue?
  end_date.present? && end_date < Date.current && progress_percent < 100
end
```

## 2 y 3. `Project`

```ruby
def progress_status
  return "sin_iniciar" if project_stages.all? { |stage| stage.progress_percent.zero? }
  return "finalizado" if project_stages.all? { |stage| stage.progress_percent == 100 }
  "iniciado"
end

def overdue?
  end_date.present? && end_date < Date.current && progress_status != "finalizado"
end
```

(`end_date` ya existe en `Project` — es el máximo de `end_date` entre sus etapas. Un proyecto sin ninguna etapa con fecha de fin tiene `end_date` `nil`, por lo tanto `overdue?` es `false`, consistente con la regla "sin fecha, nunca vencido".)

No se llama `status` en ninguno de los dos modelos porque `Project` ya tiene una columna `status` (activo/archivado) — un método con el mismo nombre chocaría con el atributo de ActiveRecord.

## 4. Badges

`app/helpers/application_helper.rb` agrega (mismo patrón que `status_label`/`status_badge`, ya existente):

```ruby
PROGRESS_STATUS_LABELS = { "sin_iniciar" => "Sin iniciar", "iniciado" => "Iniciado", "finalizado" => "Finalizado" }.freeze
PROGRESS_STATUS_BADGE_CLASSES = { "sin_iniciar" => "bg-secondary", "iniciado" => "bg-info text-dark", "finalizado" => "bg-success" }.freeze

def progress_status_label(progress_status)
  PROGRESS_STATUS_LABELS.fetch(progress_status, progress_status)
end

def progress_status_badge(progress_status)
  tag.span(progress_status_label(progress_status), class: "badge #{PROGRESS_STATUS_BADGE_CLASSES.fetch(progress_status, 'bg-light text-dark')}")
end

def overdue_badge
  tag.span("Vencido", class: "badge bg-danger")
end
```

**Uso:**

- `projects/show.html.erb` (encabezado): junto al `status_badge(@project.status)` ya existente, se agrega `progress_status_badge(@project.progress_status)` y, si `@project.overdue?`, `overdue_badge`.
- `projects/tracker.html.erb` (franja por proyecto): mismo agregado junto al `status_badge(project.status)` de cada bloque.
- `projects/_stage_table.html.erb` (compartida por ambas vistas): nueva columna "Estado" con `progress_status_badge(stage.progress_status)` + `overdue_badge` si `stage.overdue?`.

## Testing

- Modelo: `ProjectStage#progress_status` — 0%, 50%, 100%.
- Modelo: `ProjectStage#overdue?` — con fecha pasada y progreso <100 (true), con fecha pasada y progreso 100 (false), sin fecha (false), con fecha futura (false).
- Modelo: `Project#progress_status` — todas las etapas en 0 (sin_iniciar), todas en 100 (finalizado), mezcla (iniciado).
- Modelo: `Project#overdue?` — mismos casos que `ProjectStage#overdue?`, pero contra `Project#end_date`.
- Helper: `progress_status_badge`/`overdue_badge` — clases y texto correctos.
- Controlador: `show`/`tracker` — los badges nuevos aparecen en el encabezado/franja y en la tabla de etapas con los datos correctos.

## Edge cases

- Un proyecto sin ninguna etapa (caso ya cubierto en specs previos como "imposible en la práctica" pero manejado): `project_stages.all?` sobre una colección vacía devuelve `true` para ambos `all?` — el primero (`all? { progress_percent.zero? }`) ganaría primero por orden de evaluación, clasificando como `"sin_iniciar"`. Es un caso límite razonable (un proyecto sin etapas no ha avanzado nada).
- Una etapa con `progress_percent` en 100 pero `end_date` en el pasado: `overdue?` es `false` (ya se cumplió el objetivo, no importa cuándo).
