# Preservar historial de Responsibles en ProjectResponsible — design

## Contexto

`ProjectResponsible` es la relación real proyecto↔persona (`belongs_to :responsible`, FK de Rails de verdad — a diferencia del mecanismo `reference` de `custom_fields`, que hoy no usa ningún campo activo y queda fuera de este trabajo). El problema no es la resolución del nombre (siempre es correcta, vía la asociación), sino que `Responsible has_many :project_responsibles, dependent: :destroy`: al borrar un Responsible (ej. un instalador que se fue de la empresa) se borra en cascada **todo el historial** de a qué proyectos estuvo asignado. Las vistas (`app/views/projects/show.html.erb:159-160`) muestran `pr.responsible.name` y `pr.responsible.color` en vivo, sin ninguna copia.

## Alcance

1. **Denormalizar `name`/`color`** del `Responsible` en cada `ProjectResponsible`, en el momento de la asignación.
2. **Resincronizar automáticamente** esas columnas cuando el `Responsible` referenciado cambia de nombre o color (no es un snapshot congelado — se comporta como una FK real mientras el `Responsible` existe).
3. **Preservar la fila al borrar el `Responsible`**: pasar de `dependent: :destroy` a `dependent: :nullify` en `Responsible#project_responsibles`, para que la asignación quede histórica (con el nombre/color ya copiados) en vez de desaparecer.
4. **Indicador visual**: cuando `responsible_id` es `nil` (el Responsible fue borrado), la vista agrega `" (eliminado)"` junto al nombre copiado.

Fuera de alcance: lo mismo le pasa a `ResponsibleType` (`dependent: :destroy` también, mismo riesgo) — es una categoría (ej. "Instalador"), no una persona; se deja para una iteración futura. Los selects de filtro en `tracker.html.erb`/`_project_type_section.html.erb` siguen consultando `Responsible` en vivo (eligen asignaciones activas, no muestran historial) — no cambian. El mecanismo `reference` de `custom_fields` (sin uso activo hoy) no se toca en este trabajo.

## 1. Migración

```ruby
class AddResponsibleSnapshotToProjectResponsibles < ActiveRecord::Migration[7.2]
  def up
    add_column :project_responsibles, :responsible_name, :string
    add_column :project_responsibles, :responsible_color, :string
    change_column_null :project_responsibles, :responsible_id, true

    execute <<~SQL
      UPDATE project_responsibles
      SET responsible_name = responsibles.name, responsible_color = responsibles.color
      FROM responsibles
      WHERE project_responsibles.responsible_id = responsibles.id
    SQL

    change_column_null :project_responsibles, :responsible_name, false
    change_column_null :project_responsibles, :responsible_color, false
  end

  def down
    change_column_null :project_responsibles, :responsible_id, false
    remove_column :project_responsibles, :responsible_color
    remove_column :project_responsibles, :responsible_name
  end
end
```

(Backfill directo con SQL porque solo copia datos ya consistentes de un join simple — no hay riesgo de reventar contra una validación futura como en la migración `installers→responsibles`, así que no hace falta un modelo de migración descartable acá.)

## 2. `ProjectResponsible`

```ruby
class ProjectResponsible < ApplicationRecord
  belongs_to :project
  belongs_to :responsible, optional: true
  belongs_to :responsible_type
  belongs_to :project_stage, optional: true

  before_validation :snapshot_responsible, if: -> { responsible_id_changed? && responsible.present? }

  validates :responsible_id, uniqueness: { scope: [:project_id, :responsible_type_id, :project_stage_id] }, allow_nil: true
  validate :project_stage_belongs_to_project
  validate :responsible_type_belongs_to_project_type
  validate :responsible_enabled_for_project_type

  def project_wide?
    project_stage_id.nil?
  end

  private

  def snapshot_responsible
    self.responsible_name = responsible.name
    self.responsible_color = responsible.color
  end

  def project_stage_belongs_to_project
    return if project_stage.nil? || project.nil?
    errors.add(:project_stage, "debe pertenecer al mismo proyecto") unless project_stage.project_id == project.id
  end

  def responsible_type_belongs_to_project_type
    return if responsible_type.nil? || project.nil?
    errors.add(:responsible_type, "debe pertenecer al tipo de este proyecto") unless responsible_type.project_type_id == project.project_type_id
  end

  def responsible_enabled_for_project_type
    return if responsible.nil? || project.nil?
    errors.add(:responsible, "no está habilitado para este tipo de proyecto") unless responsible.project_types.include?(project.project_type)
  end
end
```

Notas:
- `validates :responsible_id, uniqueness: ..., allow_nil: true` — evita que múltiples filas históricas (todas con `responsible_id: nil`) choquen entre sí por unicidad; Postgres ya trata `NULL` como distinto en el índice único existente, pero el `allow_nil` en la validación de Rails evita una consulta de unicidad innecesaria contra `nil`.
- `snapshot_responsible` solo corre cuando `responsible_id` cambia Y hay un `responsible` (evita pisar el snapshot en updates que no tocan la asignación, ej. cambiar `project_stage_id`).
- `dependent: :nullify` (ver `Responsible` abajo) actualiza la fila por SQL directo (`update_all`), sin pasar por `before_validation`/`validates` — el snapshot ya copiado no se toca ni se re-valida al nullificar.

## 3. `Responsible`

```ruby
class Responsible < ApplicationRecord
  belongs_to :user, optional: true
  has_many :project_responsibles, dependent: :nullify
  has_many :responsible_project_types, dependent: :destroy
  has_many :project_types, through: :responsible_project_types

  validates :name, presence: true
  validates :color, format: { with: /\A#[0-9a-fA-F]{6}\z/, message: "debe ser un color hexadecimal (ej. #6c757d)" }
  validates :user_id, uniqueness: true, allow_nil: true

  after_update :resync_project_responsibles_snapshot, if: -> { saved_change_to_name? || saved_change_to_color? }

  private

  def resync_project_responsibles_snapshot
    project_responsibles.update_all(responsible_name: name, responsible_color: color)
  end
end
```

## 4. Vista `app/views/projects/show.html.erb`

Reemplazar (alrededor de la línea 159-160):

```erb
<span class="badge me-2" style="background-color: <%= pr.responsible.color %>">&nbsp;</span>
<%= pr.responsible.name %> — <%= pr.responsible_type.name %>
```

por:

```erb
<span class="badge me-2" style="background-color: <%= pr.responsible_color %>">&nbsp;</span>
<%= pr.responsible_name %><%= " (eliminado)" if pr.responsible_id.nil? %> — <%= pr.responsible_type.name %>
```

(`@project.project_responsibles.includes(:responsible, :responsible_type, :project_stage)` en la línea 156 puede seguir el `includes(:responsible, ...)` tal cual — ya no se usa para leer nombre/color, pero no molesta dejarlo, y otras partes del bloque (ej. acciones de editar/borrar la asignación) sí podrían necesitar el `Responsible` vivo.)

## Testing

Minitest, mismo patrón que el resto del proyecto (fixtures + `ActiveSupport::TestCase`/`ActionDispatch::IntegrationTest`).

- `ProjectResponsible` — crear una asignación copia `name`/`color` del `Responsible` en `responsible_name`/`responsible_color`.
- `Responsible` — renombrar un `Responsible` (o cambiarle el color) actualiza `responsible_name`/`responsible_color` en todos sus `project_responsibles` existentes.
- `Responsible` — borrar un `Responsible` con asignaciones existentes NO borra las filas de `project_responsibles`; quedan con `responsible_id: nil` y conservan `responsible_name`/`responsible_color`.
- Vista `projects/show` — una asignación histórica (`responsible_id: nil`) muestra el nombre copiado seguido de "(eliminado)"; una asignación activa no muestra esa marca.
- Regresión: crear/editar una asignación (`ProjectResponsiblesController`) sigue funcionando igual que hoy (mismas validaciones de unicidad, stage, tipo habilitado).

## Edge cases

- Cambiar el `project_stage_id` de una asignación existente (sin tocar `responsible_id`) no dispara `snapshot_responsible` — el nombre/color ya copiados quedan como estaban (correcto, no hay nada que resincronizar).
- Un `Responsible` sin ninguna asignación se borra igual que hoy (`dependent: :nullify` sobre cero filas es un no-op).
- Los selects de filtro (`tracker.html.erb`, `_project_type_section.html.erb`) siguen construyéndose contra `Responsible.joins(:project_responsibles)...` — como ahora exigen `responsible_id` no nulo implícitamente vía el `JOIN`, las asignaciones históricas (`responsible_id: nil`) quedan naturalmente afuera de esos filtros (no se puede filtrar por alguien que ya no existe), sin cambios de código.
