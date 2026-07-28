# Accesos por tipo de proyecto + UI de accesos escalable — design

## Contexto

Hoy un gerente solo puede recibir permiso de edición proyecto por proyecto (`ProjectAccess`), y la UI de asignación en `/admin/users/:id` es una tabla de checkboxes, uno por proyecto — con 2 `ProjectType` y pocos proyectos hoy funciona, pero no escala: con 200 proyectos se vuelve inmanejable, y además obliga al admin a reasignar manualmente cada proyecto nuevo que cree un gerente sin acceso previo a ese tipo.

Pedido: que un gerente pueda recibir acceso de edición a un **tipo de proyecto completo** (todos los proyectos de ese tipo, incluidos los que se creen después), y que la lista de proyectos individuales tenga una forma de encontrar uno sin scrollear 200 filas.

## Alcance

- **Nuevo modelo `ProjectTypeAccess`** (`user_id`, `project_type_id`, `can_edit`): un gerente con una fila `can_edit: true` para un `ProjectType` puede editar **todos** los proyectos de ese tipo, presentes y futuros — es una regla dinámica (se resuelve en cada chequeo, no una foto de proyectos existentes).
- **Coexiste con `ProjectAccess`**: un gerente puede tener acceso de tipo completo a "Instalaciones" y además un permiso puntual a un proyecto de otro tipo al que no tiene acceso general. `can_edit_project?` es `true` si cualquiera de las dos fuentes lo autoriza.
- **Solo afecta edición de gerentes**: `ProjectTypeAccess` no tiene columna "ver" — el gerente ya ve todos los proyectos por rol (sin cambios). El visor sigue siendo estrictamente por proyecto individual (`ProjectAccess`), no se le agrega acceso por tipo — no fue pedido y el diseño original de visor ("proyectos puntuales a los que el admin lo agregó") se mantiene.
- **UI de `/admin/users/:id`**: la sección "Accesos a proyectos" se divide en dos:
  1. **Tipos de proyecto**: una tabla chica (una fila por `ProjectType`, hoy son 2) con un solo checkbox "Editar" — la forma normal de asignar un gerente.
  2. **Proyectos individuales**: la tabla existente (ahora una sola tabla plana con columna "Tipo" en vez de agrupada), con un buscador de texto arriba que filtra las filas por nombre en el momento (JS vanilla, sin librería nueva) — para el caso de un visor con acceso puntual, o un permiso de excepción para un gerente.

Fuera de alcance: acceso por tipo para visor, un selector tipo "tags"/autocompletar (se eligió el buscador simple), cambiar cómo `ProjectsController#create`/`ImportsController#create` otorgan el permiso automático al crear (siguen creando una fila `ProjectAccess` puntual — redundante si el creador ya tiene acceso al tipo completo, pero inofensivo, no vale la pena optimizar).

## Diseño

### Migración y modelo

```ruby
class CreateProjectTypeAccesses < ActiveRecord::Migration[7.2]
  def change
    create_table :project_type_accesses do |t|
      t.references :user, null: false, foreign_key: true
      t.references :project_type, null: false, foreign_key: true
      t.boolean :can_edit, null: false, default: false

      t.timestamps

      t.index [:user_id, :project_type_id], unique: true
    end
  end
end
```

```ruby
# app/models/project_type_access.rb
class ProjectTypeAccess < ApplicationRecord
  belongs_to :user
  belongs_to :project_type

  validates :user_id, uniqueness: { scope: :project_type_id }
end
```

### `User`

```ruby
has_many :project_type_accesses, dependent: :destroy

def can_edit_project?(project)
  return true if admin?
  return false if visor?
  project_accesses.exists?(project_id: project.id, can_edit: true) ||
    project_type_accesses.exists?(project_type_id: project.project_type_id, can_edit: true)
end
```

`can_view_project?` no cambia — el visor sigue exclusivamente por `ProjectAccess`.

### `Admin::UsersController`

`edit` gana `@project_types = ProjectType.all` (además del `@projects` existente). `sync_project_accesses!` (se renombra a `sync_access_grants!` ya que ahora sincroniza dos tablas) sigue detrás del mismo marcador `sync_project_access` — un solo formulario de accesos, sin agregar un tercer `form_with`:

```ruby
def sync_access_grants!
  return unless params[:sync_project_access] == "1"

  submitted_projects = params.fetch(:project_access, {})
  @user.project_accesses.destroy_all
  submitted_projects.each do |project_id, flags|
    next unless flags["view"] == "1"
    @user.project_accesses.create!(project_id: project_id, can_edit: flags["edit"] == "1")
  end

  submitted_types = params.fetch(:project_type_access, {})
  @user.project_type_accesses.destroy_all
  submitted_types.each do |project_type_id, flags|
    next unless flags["edit"] == "1"
    @user.project_type_accesses.create!(project_type_id: project_type_id, can_edit: true)
  end
end
```

### Vista (`admin/users/_form.html.erb`, sección "Accesos a proyectos")

```erb
<h3 class="h6">Tipos de proyecto</h3>
<p class="text-muted small">Da acceso de edición a todos los proyectos de ese tipo, incluidos los que se creen después.</p>
<table class="table table-sm">
  <thead><tr><th>Tipo de proyecto</th><th>Editar</th></tr></thead>
  <tbody>
    <% @project_types.each do |project_type| %>
      <% type_access = user.project_type_accesses.find { |a| a.project_type_id == project_type.id } %>
      <tr>
        <td><%= project_type.name %></td>
        <td><%= check_box_tag "project_type_access[#{project_type.id}][edit]", "1", type_access&.can_edit || false, form: "user-access-form" %></td>
      </tr>
    <% end %>
  </tbody>
</table>

<h3 class="h6 mt-4">Proyectos individuales</h3>
<p class="text-muted small">
  "Ver" alcanza para un rol Visor. "Editar" da acceso puntual a un proyecto fuera de su
  tipo asignado (solo tiene efecto extra para un rol Gerente; Admin siempre tiene acceso total).
</p>
<%= text_field_tag :project_access_search, nil, class: "form-control mb-2", placeholder: "Buscar proyecto...", id: "project-access-search" %>
<table class="table table-sm" id="project-access-table">
  <thead><tr><th>Proyecto</th><th>Tipo</th><th>Ver</th><th>Editar</th></tr></thead>
  <tbody>
    <% @projects.each do |project| %>
      <% access = user.project_accesses.find { |a| a.project_id == project.id } %>
      <tr data-name="<%= project.name.downcase %>">
        <td><%= project.name %></td>
        <td><%= project.project_type.name %></td>
        <td><%= check_box_tag "project_access[#{project.id}][view]", "1", access.present?, form: "user-access-form" %></td>
        <td><%= check_box_tag "project_access[#{project.id}][edit]", "1", access&.can_edit || false, form: "user-access-form" %></td>
      </tr>
    <% end %>
  </tbody>
</table>
<script>
  document.getElementById("project-access-search").addEventListener("input", function (e) {
    var term = e.target.value.toLowerCase();
    document.querySelectorAll("#project-access-table tbody tr").forEach(function (row) {
      row.style.display = row.dataset.name.includes(term) ? "" : "none";
    });
  });
</script>
```

Esto reemplaza el `@projects.group_by(&:project_type).each do |project_type, projects|` actual (una tabla por tipo) por una sola tabla plana con columna "Tipo" — más simple de filtrar con un solo buscador, y la agrupación por tipo ya no aporta tanto ahora que existe la sección de arriba para asignación masiva por tipo.

El resto de la tarjeta "Accesos a proyectos" (el `admin_card`, el `form_with url: admin_user_path(user)... id: "user-access-form"` con el `hidden_field_tag "sync_project_access", "1"`) no cambia de estructura, solo el contenido interno.

## Testing

- Modelo: `ProjectTypeAccess` válido con user+project_type; inválido con par duplicado.
- Modelo: `User#can_edit_project?` — un gerente con `ProjectTypeAccess(can_edit: true)` para el tipo de un proyecto puede editarlo aunque no tenga `ProjectAccess` para ese proyecto puntual; un gerente sin ninguna de las dos fuentes no puede; un proyecto nuevo creado después bajo un tipo ya otorgado también es editable (sin crear una fila nueva — se resuelve dinámicamente).
- Controlador: `Admin::UsersController#update` con `project_type_access` params crea/reemplaza filas de `ProjectTypeAccess` igual que ya hace con `project_access`, detrás del mismo marcador `sync_project_access` (incluye el mismo caso ya cubierto de "guardar el formulario de datos del usuario sin el marcador no toca los accesos existentes", ahora también para accesos por tipo).
- Vista: `admin/users#edit` renderiza la tabla de tipos de proyecto y la tabla plana de proyectos individuales con el buscador; no se agrega test de comportamiento del filtro en sí (es JS puro, sin server-side, mismo criterio que otros scripts de esta app — verificación manual).

## Edge cases

- Un proyecto cuyo `ProjectType` fue borrado no puede existir (`ProjectType has_many :projects, dependent: :restrict_with_error`), así que `project.project_type_id` siempre resuelve a un tipo válido — sin caso nulo que manejar en `can_edit_project?`.
- Un gerente con acceso de tipo completo Y una fila `ProjectAccess(can_edit: false)` puntual para un proyecto de ese mismo tipo: el `||` en `can_edit_project?` hace que el acceso por tipo gane igual — no hay forma de "revocar" un proyecto puntual dentro de un tipo ya otorgado completo. No se pidió esa granularidad; documentado como comportamiento esperado, no bug.
