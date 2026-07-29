# Responsables de proyecto (multi-responsable, por tipo, por etapa) — design

## Contexto

Hoy un proyecto tiene un único "instalador", modelado como un catálogo simple (`Installer`: nombre + color) referenciado vía un campo dinámico (`FieldDefinition` con `data_type: "reference", reference_table: "installers"`) guardado en `custom_fields`. Se usa para filtrar el listado/tracker, colorear el Gantt general y asignar en bloque.

En la práctica un proyecto puede tener **muchos** responsables, de **distintos tipos** (instalador, diseñador, y otros que se agreguen), algunos aplicando a todo el proyecto y otros solo a una etapa puntual. Además, algunos responsables (no todos) tienen una cuenta de usuario del sistema y deberían poder loguearse y ver/actualizar lo que tienen asignado.

Este documento reemplaza por completo el mecanismo de "instalador" por un modelo de asignaciones múltiples.

## Alcance

- **Catálogo de tipos por tipo de proyecto** (`ResponsibleType`): cada `ProjectType` define su propia lista de tipos de responsable posibles (Instalador, Diseñador, etc.), mismo patrón administrativo que `FieldDefinition`/`StageTemplate`.
- **Catálogo global de personas** (`Responsible`): reemplaza a `Installer`. Nombre, color propio, y vínculo opcional a un `User`.
- **Asignaciones** (`ProjectResponsible`): une un `Responsible` a un `Project`, con qué `ResponsibleType` actúa ahí, y opcionalmente a una `ProjectStage` puntual (si no hay etapa, aplica a todo el proyecto). El tipo se define en cada asignación, no en la persona — el mismo `Responsible` puede ser "Instalador" en un proyecto y "Diseñador" en otro.
- **Nuevo rol `responsable`**: un `User` vinculado a un `Responsible` que se loguea con este rol ve únicamente los proyectos donde tiene alguna asignación, y puede editar el `progress_percent` de las etapas donde está asignado directamente o donde está asignado a nivel de todo el proyecto (en ese caso, edita todas las etapas de ese proyecto). No edita nada más del proyecto.
- **Migración de datos**: cada `Installer` existente pasa a ser un `Responsible` de tipo "Instalador" (creado por tipo de proyecto que use el campo `installers`), y cada proyecto con instalador cargado obtiene la asignación equivalente a nivel de todo el proyecto. El campo dinámico "Instalador" se elimina de los tipos de proyecto migrados. El modelo `Installer`, su controlador/vistas/rutas y la tabla `installers` se eliminan por completo.
- **Filtro, color de Gantt y asignación masiva** en el listado/tracker de proyectos se adaptan al nuevo modelo: dos dropdowns encadenados (tipo → responsable), coloreado condicionado al tipo elegido, asignación masiva a nivel de todo el proyecto para el tipo elegido.

Fuera de alcance: tipos de responsable compartidos entre tipos de proyecto (cada `ProjectType` tiene su lista propia, sin herencia ni catálogo global de tipos); permitir editar fechas de etapa desde el rol `responsable` (solo `progress_percent`); colorear por más de un tipo a la vez en el Gantt general; deshacer/histórico de asignaciones más allá de lo que ya cubre `PaperTrail` en los modelos que ya lo tienen.

## Diseño

### Modelos

```ruby
# Migración: create_table :responsible_types
create_table :responsible_types do |t|
  t.references :project_type, null: false, foreign_key: true
  t.string :name, null: false
  t.timestamps
  t.index [:project_type_id, :name], unique: true
end
```

```ruby
# app/models/responsible_type.rb
class ResponsibleType < ApplicationRecord
  belongs_to :project_type
  has_many :project_responsibles, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :project_type_id }
end
```

```ruby
# Migración: create_table :responsibles
create_table :responsibles do |t|
  t.string :name, null: false
  t.string :color, default: "#6c757d", null: false
  t.references :user, null: true, foreign_key: true
  t.timestamps
  t.index [:user_id], unique: true
end
```

```ruby
# app/models/responsible.rb
class Responsible < ApplicationRecord
  belongs_to :user, optional: true
  has_many :project_responsibles, dependent: :destroy

  validates :name, presence: true
  validates :color, format: { with: /\A#[0-9a-fA-F]{6}\z/, message: "debe ser un color hexadecimal (ej. #6c757d)" }
end
```

```ruby
# Migración: create_table :project_responsibles
create_table :project_responsibles do |t|
  t.references :project, null: false, foreign_key: true
  t.references :responsible, null: false, foreign_key: true
  t.references :responsible_type, null: false, foreign_key: true
  t.references :project_stage, null: true, foreign_key: true
  t.timestamps
  t.index [:project_id, :responsible_id, :responsible_type_id, :project_stage_id],
    unique: true, name: "index_project_responsibles_on_assignment"
end
```

```ruby
# app/models/project_responsible.rb
class ProjectResponsible < ApplicationRecord
  belongs_to :project
  belongs_to :responsible
  belongs_to :responsible_type
  belongs_to :project_stage, optional: true

  validates :responsible_id, uniqueness: { scope: [:project_id, :responsible_type_id, :project_stage_id] }
  validate :project_stage_belongs_to_project
  validate :responsible_type_belongs_to_project_type

  def project_wide?
    project_stage_id.nil?
  end

  private

  def project_stage_belongs_to_project
    return if project_stage.nil? || project.nil?
    errors.add(:project_stage, "debe pertenecer al mismo proyecto") unless project_stage.project_id == project.id
  end

  def responsible_type_belongs_to_project_type
    return if responsible_type.nil? || project.nil?
    errors.add(:responsible_type, "debe pertenecer al tipo de este proyecto") unless responsible_type.project_type_id == project.project_type_id
  end
end
```

### `Project`, `ProjectStage`

```ruby
# app/models/project.rb
has_many :project_responsibles, dependent: :destroy

def responsible_for(responsible_type)
  project_responsibles.find { |pr| pr.responsible_type_id == responsible_type.id && pr.project_wide? }&.responsible
end
```

```ruby
# app/models/project_stage.rb
has_many :project_responsibles, dependent: :destroy
```

### `User`

```ruby
enum :role, { admin: "admin", gerente: "gerente", visor: "visor", responsable: "responsable" }, default: "visor"

has_one :responsible, dependent: :nullify

def can_view_project?(project)
  return true if admin? || gerente?
  return project_accesses.exists?(project_id: project.id) if visor?
  return false if responsible.nil?
  ProjectResponsible.where(project_id: project.id, responsible_id: responsible.id).exists?
end

def editable_project_stage_ids(project)
  return project.project_stage_ids if admin? || (gerente? || visor?) && can_edit_project?(project)
  return [] if responsible.nil?

  assignments = ProjectResponsible.where(project_id: project.id, responsible_id: responsible.id)
  return project.project_stage_ids if assignments.any?(&:project_wide?)
  assignments.filter_map(&:project_stage_id)
end
```

`can_edit_project?` (edición completa: nombre, campos, todas las etapas) **no cambia** — sigue siendo exclusiva de admin/gerente-con-acceso. `editable_project_stage_ids` es el método nuevo que gobierna qué etapas puede tocar un `responsable` (o, para admin/gerente, todas). La vista/controlador de edición se apoyan en este método, no en `can_edit_project?`, para decidir qué campos de avance mostrar/aceptar.

### `Project.visible_to`

```ruby
def self.visible_to(user)
  return all if user.admin? || user.gerente?
  return joins(:project_accesses).where(project_accesses: { user_id: user.id }) if user.visor?
  return none if user.responsible.nil?
  joins(:project_responsibles).where(project_responsibles: { responsible_id: user.responsible.id }).distinct
end
```

### Admin: catálogo de personas (`Admin::ResponsiblesController`)

Reemplaza a `Admin::InstallersController` — mismas rutas (`resources :responsibles`), mismo patrón de formulario (`admin_card`), agregando un `select` opcional para vincular un `User` (solo los que no tengan ya un `Responsible` — `User.where(responsible: nil)`, más el usuario actualmente vinculado si se está editando).

### Admin: tipos por proyecto (`Admin::ProjectTypes::ResponsibleTypesController`)

Anidado bajo `project_type`, mismo patrón que `field_definitions`/`stage_templates` (`except: [:index, :show]`, sin reorder — no hace falta orden, se listan alfabéticamente). Se agrega una cuarta tarjeta "Tipos de responsable" en `admin/project_types/show.html.erb`, calcada de la de "Tipos de Bitácora" (sin drag-reorder).

```ruby
# app/controllers/admin/project_types/responsible_types_controller.rb
class Admin::ProjectTypes::ResponsibleTypesController < Admin::BaseController
  before_action :set_project_type
  before_action :set_responsible_type, only: [:edit, :update, :destroy]

  def new
    @responsible_type = @project_type.responsible_types.new
  end

  def create
    @responsible_type = @project_type.responsible_types.new(responsible_type_params)
    if @responsible_type.save
      redirect_to admin_project_type_path(@project_type)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @responsible_type.update(responsible_type_params)
      redirect_to admin_project_type_path(@project_type)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @responsible_type.destroy
    redirect_to admin_project_type_path(@project_type)
  end

  private

  def set_project_type
    @project_type = ProjectType.find(params[:project_type_id])
  end

  def set_responsible_type
    @responsible_type = @project_type.responsible_types.find(params[:id])
  end

  def responsible_type_params
    params.require(:responsible_type).permit(:name)
  end
end
```

Routes:

```ruby
resources :project_types do
  # ...
  resources :responsible_types, except: [:index, :show]
end
```

### Asignar responsables en el proyecto (`ProjectResponsiblesController`)

Nested bajo `projects`, solo `create`/`destroy` (mismo patrón que `log_entries`):

```ruby
resources :projects do
  resources :log_entries, only: [:create, :destroy]
  resources :project_responsibles, only: [:create, :destroy]
end
```

```ruby
# app/controllers/project_responsibles_controller.rb
class ProjectResponsiblesController < ApplicationController
  before_action :set_project
  before_action :authorize_edit!

  def create
    @project_responsible = @project.project_responsibles.new(project_responsible_params)
    if @project_responsible.save
      redirect_to project_path(@project)
    else
      redirect_to project_path(@project), alert: @project_responsible.errors.full_messages.to_sentence
    end
  end

  def destroy
    @project.project_responsibles.find(params[:id]).destroy
    redirect_to project_path(@project)
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end

  def authorize_edit!
    return if current_user.can_edit_project?(@project)
    redirect_to root_path, alert: "No tenés permiso para hacer eso."
  end

  def project_responsible_params
    params.require(:project_responsible).permit(:responsible_id, :responsible_type_id, :project_stage_id)
  end
end
```

En `projects/show.html.erb`, una tarjeta "Responsables" (visible solo si `current_user.can_edit_project?(@project)`):

```erb
<% if current_user.can_edit_project?(@project) %>
  <div class="card mb-4">
    <div class="card-header">Responsables</div>
    <div class="card-body">
      <ul class="list-group list-group-flush mb-3">
        <% @project.project_responsibles.includes(:responsible, :responsible_type, :project_stage).each do |pr| %>
          <li class="list-group-item d-flex justify-content-between align-items-center">
            <span>
              <span class="badge me-2" style="background-color: <%= pr.responsible.color %>">&nbsp;</span>
              <%= pr.responsible.name %> — <%= pr.responsible_type.name %>
              (<%= pr.project_stage&.name || "Todo el proyecto" %>)
            </span>
            <%= button_to "Quitar", project_project_responsible_path(@project, pr), method: :delete,
                  class: "btn btn-outline-danger btn-sm", form: { style: "display:inline-block", onsubmit: "return confirm('¿Quitar responsable?')" } %>
          </li>
        <% end %>
      </ul>
      <%= form_with model: [@project, ProjectResponsible.new], url: project_project_responsibles_path(@project) do |form| %>
        <div class="row g-2">
          <div class="col-auto">
            <%= form.collection_select :responsible_id, Responsible.order(:name), :id, :name, { include_blank: "Responsable" }, class: "form-select" %>
          </div>
          <div class="col-auto">
            <%= form.collection_select :responsible_type_id, @project.project_type.responsible_types.order(:name), :id, :name, { include_blank: "Tipo" }, class: "form-select" %>
          </div>
          <div class="col-auto">
            <%= form.collection_select :project_stage_id, @project.project_stages, :id, :name, { include_blank: "Todo el proyecto" }, class: "form-select" %>
          </div>
          <div class="col-auto">
            <%= form.submit "Agregar", class: "btn btn-primary" %>
          </div>
        </div>
      <% end %>
    </div>
  </div>
<% end %>
```

### Edición restringida para el rol `responsable`

`ProjectsController#authorize_edit!` pasa de exigir `can_edit_project?` a exigir `can_edit_project? || editable_project_stage_ids(@project).any?`. En `edit`/`update`:

```ruby
def edit
  @editable_stage_ids = current_user.editable_project_stage_ids(@project)
end

def update
  if current_user.can_edit_project?(@project)
    if @project.update(project_params)
      redirect_to project_path(@project)
    else
      @editable_stage_ids = current_user.editable_project_stage_ids(@project)
      render :edit, status: :unprocessable_entity
    end
  else
    update_progress_only!
  end
end

private

def update_progress_only!
  editable_ids = current_user.editable_project_stage_ids(@project).map(&:to_s)
  submitted = params.fetch(:project, {}).fetch(:project_stages_attributes, {})
  submitted.each do |_, attrs|
    next unless editable_ids.include?(attrs["id"].to_s)
    @project.project_stages.find(attrs["id"]).update!(progress_percent: attrs["progress_percent"])
  end
  redirect_to project_path(@project)
end
```

La vista `edit.html.erb` renderiza el formulario completo actual si `current_user.can_edit_project?(@project)`; si no (pero `@editable_stage_ids.any?`), renderiza un parcial nuevo y más chico, `_progress_only_form.html.erb`, con un input de `progress_percent` por cada etapa en `@editable_stage_ids` y nada más.

### Migración de datos

Una migración de datos (`db/migrate/..._migrate_installers_to_responsibles.rb`), después de crear las tres tablas nuevas y antes de dropear `installers`. Corre después de que `ResponsibleType`/`Responsible`/`ProjectResponsible` ya existen en el código de la app, así que usa esos modelos ActiveRecord directamente (no SQL crudo — es una migración de datos, no de esquema):

```ruby
class MigrateInstallersToResponsibles < ActiveRecord::Migration[7.2]
  def up
    installer_fields = FieldDefinition.where(reference_table: "installers")
    return if installer_fields.none?

    responsible_type_by_project_type = installer_fields.pluck(:project_type_id).uniq.index_with do |pt_id|
      ResponsibleType.create!(project_type_id: pt_id, name: "Instalador")
    end

    installer_to_responsible = Installer.all.to_h do |installer|
      [installer.id, Responsible.create!(name: installer.name, color: installer.color)]
    end

    installer_fields.each do |field|
      responsible_type = responsible_type_by_project_type[field.project_type_id]
      Project.where(project_type_id: field.project_type_id).find_each do |project|
        installer_id = project.custom_fields[field.key]
        next if installer_id.blank?
        responsible = installer_to_responsible[installer_id.to_i]
        next if responsible.nil?
        ProjectResponsible.create!(project: project, responsible: responsible, responsible_type: responsible_type)
      end
    end

    installer_fields.destroy_all
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
```

El orden importa: crear tipos → crear responsables → crear asignaciones → borrar los `FieldDefinition` de instalador, y esta migración corre después de que las tres tablas nuevas existan (migraciones separadas y anteriores en el mismo PR).

Migración final, después de confirmar que los datos se copiaron:

```ruby
class DropInstallers < ActiveRecord::Migration[7.2]
  def change
    drop_table :installers do |t|
      t.string :name, null: false
      t.string :color, default: "#6c757d", null: false
      t.timestamps
    end
  end
end
```

Se elimina además: `app/models/installer.rb`, `app/controllers/admin/installers_controller.rb`, `app/views/admin/installers/*`, la ruta `resources :installers` dentro de `namespace :admin`, y todo lo que hoy referencia `Installer`/`installer_id` en `ProjectsController` y las vistas de proyectos (ver siguiente sección — se reemplaza, no queda código muerto).

### Filtro, color de Gantt y asignación masiva

En `ProjectsController`:

```ruby
def filter_by_responsible(scope, responsible_type_id, responsible_id)
  return scope if responsible_type_id.blank?
  matching = ProjectResponsible.where(responsible_type_id: responsible_type_id)
  matching = matching.where(responsible_id: responsible_id) if responsible_id.present? && responsible_id != "none"
  if responsible_id == "none"
    scope.where.not(id: matching.select(:project_id))
  else
    scope.where(id: matching.select(:project_id))
  end
end
```

`bulk_assign_installer` se renombra a `bulk_assign_responsible`, recibe `responsible_type_id` + `responsible_id`, y por cada proyecto seleccionado hace `find_or_create_by!(responsible_type_id:, project_stage: nil) { |pr| pr.responsible_id = ... }` (upsert a nivel de todo el proyecto, reemplazando si ya había alguien de ese tipo asignado a todo el proyecto).

En `_project_type_section.html.erb`: el dropdown `installer_id` se reemplaza por dos — `responsible_type_id` (opciones: `project_type.responsible_types`) y `responsible_id` (opciones: `Responsible.joins(:project_responsibles).where(project_responsibles: { responsible_type_id: section_params[:responsible_type_id] }).distinct`, recalculado según el tipo elegido — se resuelve con una recarga de página al cambiar el tipo, igual que el resto de los filtros de esta pantalla, que ya son server-rendered vía query params). El color del Gantt usa `project.responsible_for(responsible_type)` en vez de `project.installer`, solo cuando `section_params[:responsible_type_id]` está presente.

En `tracker.html.erb`: mismo cambio de dropdown único → dos encadenados, mismo filtro.

## Testing

- Modelos: `ResponsibleType` (validaciones, scope por `project_type`), `Responsible` (validaciones, color), `ProjectResponsible` (uniqueness compuesta, `project_stage` debe pertenecer al proyecto, `responsible_type` debe pertenecer al tipo del proyecto, `project_wide?`).
- `User`: `can_view_project?`/`can_edit_project?`/`editable_project_stage_ids` para rol `responsable` — sin asignación (nada), asignado a una etapa puntual (solo esa etapa), asignado a todo el proyecto (todas las etapas), y que `can_edit_project?` siga siendo `false` para `responsable` (no tiene edición completa).
- `Project.visible_to` para rol `responsable`.
- Controladores: `Admin::ResponsiblesController`, `Admin::ProjectTypes::ResponsibleTypesController` (CRUD estándar, calcado de los tests existentes de `installers`/`log_entry_types`), `ProjectResponsiblesController` (crear/quitar asignación, solo con permiso de edición), `ProjectsController#edit`/`#update` (responsable con acceso parcial: solo puede tocar `progress_percent` de sus etapas, un request manipulado con otro `stage_id` o con `name`/`custom_fields` no tiene efecto), `ProjectsController#index`/`#tracker` (filtro de dos niveles, incluye "Sin asignar"), `bulk_assign_responsible`.
- Migración de datos: test de integración que corre la migración sobre fixtures representativas de `installers`/`field_definitions`/`projects.custom_fields` y verifica el resultado (o, si el proyecto no tiene infraestructura para testear migraciones de datos directamente, se verifica manualmente contra una copia de la base antes de aplicar en producción — el plan de implementación decide cuál es viable).

## Edge cases

- Un `Responsible` sin `user_id`: nunca puede loguearse como tal (no tiene fila en `users`); esto es el caso normal y esperado, no un error.
- Un `User` con rol `responsable` pero sin `Responsible` vinculado (se cambió el rol manualmente sin asociar): no ve ningún proyecto (`Project.visible_to` devuelve `none`) — no rompe, simplemente no ve nada hasta que un admin lo vincule.
- Borrar un `Responsible` que tiene asignaciones: se borran en cascada (`dependent: :destroy` en `ProjectResponsible`) — se pierde el historial de quién fue responsable, aceptado como comportamiento igual al resto de accesos en la app (no hay soft-delete en ningún lado del sistema hoy).
- Borrar un `ResponsibleType` en uso: mismo criterio, cascada sobre `ProjectResponsible` (a diferencia de `StageTemplate`, que sí tiene `dependent: :restrict_with_error` en dirección opuesta vía `ProjectType has_many :projects` — pero acá no hay una entidad "viva" equivalente a `Project` que dependa de forma obligatoria de `ResponsibleType`, así que cascada es seguro).
- Un `ProjectStage` se borra (proyecto se edita/regenera etapas): sus `ProjectResponsible` puntuales se borran en cascada; una asignación a nivel de todo el proyecto (`project_stage_id: nil`) no se ve afectada.
- Dos asignaciones "iguales" (mismo `responsible` + `responsible_type`, una a nivel de proyecto y otra a una etapa puntual del mismo proyecto): permitido por el índice único (difieren en `project_stage_id`) — es redundante en la práctica (la de nivel de proyecto ya cubre esa etapa) pero no se prohíbe explícitamente, no vale la pena la validación extra.
