# Responsables habilitados por tipo de proyecto — design

## Contexto

Hoy `Responsible` es un catálogo global: cualquier persona puede asignarse a un proyecto de cualquier tipo, en cualquier `ResponsibleType` de ese tipo. En la práctica, un admin quiere poder decir "Juan Pérez solo trabaja en proyectos de Instalaciones" y que Juan no aparezca como opción al asignar responsables en un proyecto de otro tipo — sin dejar de poder habilitarlo para varios tipos a la vez (relación N:M).

## Alcance

- **Nueva relación N:M** `Responsible` ↔ `ProjectType` vía un modelo `ResponsibleProjectType` — qué tipos de proyecto habilitan a cada responsable.
- **Se configura desde el formulario del responsable** (`/admin/responsibles/:id/edit`), con un checkbox por `ProjectType`.
- **Validación dura**: `ProjectResponsible` rechaza la asignación si el `Responsible` no está habilitado para el `ProjectType` del proyecto — no solo se oculta en la UI, se lo bloquea también en el modelo (mismo criterio que la validación existente de que `responsible_type` debe pertenecer al tipo del proyecto).
- **Selectores que ofrecen "a quién puedo asignar"** se filtran a solo los responsables habilitados para el tipo del proyecto en cuestión:
  - La tarjeta "Responsables" en `admin/project_types/:id` (la que ya mostraba a todos).
  - El selector "Responsable" del formulario de asignación en `projects/show.html.erb`.
  - El selector "Asignar a los seleccionados" de la asignación masiva en `_project_type_section.html.erb`.
- **Migración de datos**: cada `Responsible` que ya tiene una asignación (`ProjectResponsible`) existente queda habilitado automáticamente para el/los tipos de proyecto de esas asignaciones — nada de lo ya asignado se rompe con la nueva validación.

Fuera de alcance: tocar los selectores de **filtro** (no de asignación) que ya existen en `_project_type_section.html.erb` y `tracker.html.erb` ("Responsable" para filtrar el listado) — esos ya se acotan a "quién tiene una asignación de tal tipo" por una razón distinta (mostrar solo gente relevante para filtrar), no a "quién puede asignarse"; no hace falta cruzarlos con la nueva habilitación.

## Diseño

### Modelo

```ruby
# Migración
create_table :responsible_project_types do |t|
  t.references :responsible, null: false, foreign_key: true
  t.references :project_type, null: false, foreign_key: true
  t.timestamps
  t.index [:responsible_id, :project_type_id], unique: true, name: "index_responsible_project_types_on_pair"
end
```

```ruby
# app/models/responsible_project_type.rb
class ResponsibleProjectType < ApplicationRecord
  belongs_to :responsible
  belongs_to :project_type

  validates :responsible_id, uniqueness: { scope: :project_type_id }
end
```

```ruby
# app/models/responsible.rb — agregar
has_many :responsible_project_types, dependent: :destroy
has_many :project_types, through: :responsible_project_types
```

```ruby
# app/models/project_type.rb — agregar
has_many :responsible_project_types, dependent: :destroy
has_many :responsibles, through: :responsible_project_types
```

### Validación en `ProjectResponsible`

```ruby
# app/models/project_responsible.rb — agregar
validate :responsible_enabled_for_project_type

private

def responsible_enabled_for_project_type
  return if responsible.nil? || project.nil?
  errors.add(:responsible, "no está habilitado para este tipo de proyecto") unless responsible.project_types.include?(project.project_type)
end
```

### Admin: formulario del responsable

`app/controllers/admin/responsibles_controller.rb` — permitir `project_type_ids: []`:

```ruby
def responsible_params
  params.require(:responsible).permit(:name, :color, :user_id, project_type_ids: [])
end
```

`app/views/admin/responsibles/_form.html.erb` — agregar, antes del botón submit:

```erb
<div class="mb-3">
  <%= form.label :project_type_ids, "Tipos de proyecto habilitados", class: "form-label d-block" %>
  <% ProjectType.order(:name).each do |project_type| %>
    <div class="form-check">
      <%= check_box_tag "responsible[project_type_ids][]", project_type.id,
            responsible.project_type_ids.include?(project_type.id), class: "form-check-input", id: "project_type_ids_#{project_type.id}" %>
      <%= label_tag "project_type_ids_#{project_type.id}", project_type.name, class: "form-check-label" %>
    </div>
  <% end %>
</div>
```

(`check_box_tag` en vez de `form.collection_check_boxes` para evitar el hidden-field-de-array-vacío que `collection_check_boxes` no siempre maneja bien con `permit(project_type_ids: [])` cuando ninguno queda tildado — se agrega manualmente un `hidden_field_tag "responsible[project_type_ids][]", ""` fuera del loop para que des-tildar todos efectivamente vacíe la relación en vez de no enviar la clave.)

### Filtrar selectores de asignación

**`admin/project_types/show.html.erb`** — cambiar `Responsible.order(:name)` por `@project_type.responsibles.order(:name)` en la tarjeta "Responsables".

**`projects/show.html.erb`** (tarjeta "Responsables", formulario de alta) — cambiar:

```erb
<%= form.collection_select :responsible_id, Responsible.order(:name), :id, :name, { include_blank: "Responsable" }, class: "form-select" %>
```

por:

```erb
<%= form.collection_select :responsible_id, @project.project_type.responsibles.order(:name), :id, :name, { include_blank: "Responsable" }, class: "form-select" %>
```

**`_project_type_section.html.erb`** (bulk-assign, "Asignar a los seleccionados") — cambiar:

```erb
<%= f.select :responsible_id, Responsible.order(:name).collect { |r| [r.name, r.id] },
      { include_blank: "Elegí un responsable" }, class: "form-select", id: "bulk-assign-responsible-select-#{slug}" %>
```

por:

```erb
<%= f.select :responsible_id, project_type.responsibles.order(:name).collect { |r| [r.name, r.id] },
      { include_blank: "Elegí un responsable" }, class: "form-select", id: "bulk-assign-responsible-select-#{slug}" %>
```

### Migración de datos (backfill)

```ruby
class BackfillResponsibleProjectTypes < ActiveRecord::Migration[7.2]
  def up
    ProjectResponsible.includes(:responsible, project: :project_type).find_each do |pr|
      ResponsibleProjectType.find_or_create_by!(responsible_id: pr.responsible_id, project_type_id: pr.project.project_type_id)
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
```

## Testing

- `ResponsibleProjectType`: validaciones (par único, ambos requeridos).
- `Responsible#project_types`/`ProjectType#responsibles`: asociación funciona en ambas direcciones.
- `ProjectResponsible`: crear una asignación para un responsable no habilitado en el tipo del proyecto falla con el mensaje esperado; crear una para uno habilitado funciona.
- `Admin::ResponsiblesController`: guardar con checkboxes tildados crea las filas de habilitación correspondientes; destildar todos las borra (no las deja huérfanas).
- Vistas: la tarjeta de `project_types#show`, el selector de `projects/show.html.erb` y el de bulk-assign solo listan responsables habilitados para el tipo correspondiente.
- Migración de backfill: verificar manualmente contra la base de desarrollo (mismo criterio que la migración de datos de Installer→Responsible), ya que no hay infraestructura de test para migraciones de datos en este proyecto.

## Edge cases

- Un `Responsible` sin ningún tipo habilitado (recién creado, o con todos destildados): no aparece en ningún selector de asignación de ningún tipo — comportamiento esperado, no es un bug.
- Borrar un `ProjectType` en uso: `ResponsibleProjectType` cascada (`dependent: :destroy` en ambas puntas) — no hay nada que impida borrar un tipo de proyecto por tener responsables habilitados (mismo criterio que `ResponsibleType`, no como `Project`, que sí restringe).
