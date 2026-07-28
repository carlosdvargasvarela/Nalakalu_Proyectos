# Bitácora y log de cambios por proyecto — design

## Contexto

Usuarios del piloto piden dos cosas relacionadas pero distintas en la pantalla de un proyecto (`projects#show`):

1. Una **bitácora**: notas que los usuarios agregan manualmente (nota, incidencia, cambio), con autor y fecha.
2. Un **log de cambios automático** (tipo PaperTrail): qué campos cambiaron, cuándo y quién lo hizo, sin intervención manual.

Son dos secciones separadas, no un feed unificado.

## Alcance

**Bitácora manual:**
- Modelo `LogEntryType` (`belongs_to :project_type`, `name`, `color`) — administrable en `admin/project_types/:id` con el mismo patrón CRUD que `StageTemplate` (`Admin::StageTemplatesController`).
- Al crear un `ProjectType` se siembran automáticamente 3 `LogEntryType`: "Nota", "Incidencia", "Cambio" (editables/eliminables después, igual que las stages hoy).
- Modelo `LogEntry` (`belongs_to :project`, `belongs_to :user`, `belongs_to :log_entry_type`, `body:text`).
- Cualquier usuario autenticado puede crear entradas. Solo el autor puede editar/eliminar las suyas (`current_user == log_entry.user`, sin roles nuevos).
- Card "Bitácora" en `projects#show`, debajo del Gantt: listado cronológico (más reciente arriba) + formulario (selector de tipo + textarea) para agregar.

**Log automático de cambios:**
- Gema `paper_trail` (Gemfile).
- `has_paper_trail` en `Project`, `ProjectStage`, `ProjectType`, `FieldDefinition`, `StageTemplate`, `Installer`.
- `ApplicationController` setea `PaperTrail.request.whodunnit = current_user&.id`.
- Card "Historial de cambios" en `projects#show`, debajo de la bitácora: versiones de `@project` y sus `project_stages`, combinadas y ordenadas por fecha, mostrando campo, valor anterior → nuevo, autor y fecha.

Fuera de alcance: roles/permisos nuevos en Devise (queda para una mejora futura del módulo de usuarios, según lo indicado). Adjuntos en la bitácora. Edición de entradas de bitácora vía UI (solo eliminar; ver Diseño). Historial de cambios de `LogEntry`/`LogEntryType` en sí mismos (no llevan `has_paper_trail`).

## Diseño

### Modelos y migraciones

```ruby
# db/migrate/..._create_log_entry_types.rb
create_table :log_entry_types do |t|
  t.references :project_type, null: false, foreign_key: true
  t.string :name, null: false
  t.string :color, null: false, default: "#6c757d"
  t.timestamps
end

# db/migrate/..._create_log_entries.rb
create_table :log_entries do |t|
  t.references :project, null: false, foreign_key: true
  t.references :user, null: false, foreign_key: true
  t.references :log_entry_type, null: false, foreign_key: true
  t.text :body, null: false
  t.timestamps
end

# db/migrate/..._create_versions_and_add_paper_trail (paper_trail:install generator)
```

```ruby
# app/models/log_entry_type.rb
class LogEntryType < ApplicationRecord
  belongs_to :project_type
  has_many :log_entries, dependent: :restrict_with_error

  validates :name, presence: true
  validates :color, format: { with: /\A#[0-9a-fA-F]{6}\z/, message: "debe ser un color hexadecimal (ej. #6c757d)" }
end

# app/models/log_entry.rb
class LogEntry < ApplicationRecord
  belongs_to :project
  belongs_to :user
  belongs_to :log_entry_type

  validates :body, presence: true
end
```

`ProjectType` siembra los 3 tipos por defecto igual que hoy siembra nada para stages (las stages las crea el admin a mano) — pero acá el pedido explícito es sembrar automáticamente, así que va un `after_create` en `ProjectType`:

```ruby
# app/models/project_type.rb
after_create :seed_default_log_entry_types

private

def seed_default_log_entry_types
  %w[Nota Incidencia Cambio].each { |name| log_entry_types.create!(name: name, color: "#6c757d") }
end
```

`Project`, `ProjectStage`, `ProjectType`, `FieldDefinition`, `StageTemplate`, `Installer` agregan `has_paper_trail`.

`ApplicationController`:

```ruby
before_action :set_paper_trail_whodunnit
```

(provisto por la gema; internamente usa `current_user.id`, que ya existe vía Devise).

### Rutas

```ruby
resources :projects do
  resources :log_entries, only: [:create, :destroy]
end

resources :project_types do
  resources :log_entry_types, except: [:index, :show]
  resources :stage_templates, except: [:index, :show]
  # ...
end
```

Namespaced bajo `admin` para `log_entry_types`, igual que `stage_templates` hoy.

### Controladores

```ruby
# app/controllers/log_entries_controller.rb
class LogEntriesController < ApplicationController
  before_action :set_project

  def create
    @log_entry = @project.log_entries.new(log_entry_params.merge(user: current_user))
    if @log_entry.save
      redirect_to project_path(@project)
    else
      redirect_to project_path(@project), alert: @log_entry.errors.full_messages.to_sentence
    end
  end

  def destroy
    log_entry = @project.log_entries.find(params[:id])
    log_entry.destroy if log_entry.user == current_user
    redirect_to project_path(@project)
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end

  def log_entry_params
    params.require(:log_entry).permit(:body, :log_entry_type_id)
  end
end
```

`Admin::LogEntryTypesController` — copia directa del patrón de `Admin::StageTemplatesController` (`new`/`create`/`edit`/`update`/`destroy`, sin `reorder`).

### Vistas

`projects#show` agrega, debajo del card del Gantt existente:

```erb
<div class="card mb-4">
  <div class="card-header">Bitácora</div>
  <div class="card-body">
    <%= form_with model: LogEntry.new, url: project_log_entries_path(@project) do |f| %>
      <div class="d-flex gap-2 mb-3">
        <%= f.collection_select :log_entry_type_id, @project.project_type.log_entry_types, :id, :name, {}, class: "form-select form-select-sm w-auto" %>
        <%= f.text_area :body, class: "form-control form-control-sm", rows: 1, placeholder: "Agregar nota..." %>
        <%= f.submit "Agregar", class: "btn btn-primary btn-sm" %>
      </div>
    <% end %>
    <ul class="list-group list-group-flush">
      <% @project.log_entries.includes(:user, :log_entry_type).order(created_at: :desc).each do |entry| %>
        <li class="list-group-item d-flex justify-content-between align-items-start">
          <div>
            <span class="badge" style="background-color: <%= entry.log_entry_type.color %>"><%= entry.log_entry_type.name %></span>
            <%= entry.body %>
            <div class="text-muted small"><%= entry.user.email %> — <%= l(entry.created_at, format: :short) %></div>
          </div>
          <% if entry.user == current_user %>
            <%= button_to "Eliminar", project_log_entry_path(@project, entry), method: :delete, class: "btn btn-sm btn-outline-danger" %>
          <% end %>
        </li>
      <% end %>
    </ul>
  </div>
</div>

<div class="card mb-4">
  <div class="card-header">Historial de cambios</div>
  <div class="card-body">
    <ul class="list-group list-group-flush">
      <% @project_change_versions.each do |version| %>
        <li class="list-group-item small">
          <strong><%= version.event == "create" ? "Creado" : version.changeset.keys.join(", ") %></strong>
          por <%= version.whodunnit ? User.find_by(id: version.whodunnit)&.email : "sistema" %>
          — <%= l(version.created_at, format: :short) %>
          <% version.changeset.except("updated_at").each do |field, (before, after)| %>
            <div class="text-muted">· <%= field %>: <%= before.inspect %> → <%= after.inspect %></div>
          <% end %>
        </li>
      <% end %>
    </ul>
  </div>
</div>
```

`ProjectsController#show` arma `@project_change_versions`:

```ruby
def show
  stage_version_ids = @project.project_stages.flat_map { |s| s.versions.ids }
  version_ids = @project.versions.ids + stage_version_ids
  @project_change_versions = PaperTrail::Version.where(id: version_ids).order(created_at: :desc)
end
```

## Testing

- Modelo: `LogEntry` requiere `body`; `LogEntryType` requiere `name` y `color` con formato hex.
- Modelo: crear un `ProjectType` siembra 3 `LogEntryType` ("Nota", "Incidencia", "Cambio").
- Controlador: `LogEntriesController#create` asigna `current_user` como autor; `#destroy` solo borra si el `current_user` es el autor (un segundo usuario intentando borrar no debe eliminar el registro).
- Modelo: actualizar `Project#name` o `ProjectStage#progress_percent` genera una `PaperTrail::Version` con el `whodunnit` correcto.

## Edge cases

- `ProjectType` sin `LogEntryType`s (dato legado, creado antes de este feature): el `collection_select` queda vacío — se acepta como caso raro del piloto, no se migra retroactivamente.
- Usuario que intenta eliminar una `LogEntry` ajena vía POST directo: el controlador ignora el `destroy` silenciosamente (redirige sin borrar), no hace falta página de error ya que no hay UI que ofrezca ese botón a otros usuarios.
- `ProjectStage` eliminado: sus `PaperTrail::Version` quedan huérfanas de la etapa pero siguen existiendo — no se incluyen en el historial del proyecto tras el borrado (se listan solo las etapas actuales vía `@project.project_stages`), aceptado por ser un caso de borde raro en el piloto.
