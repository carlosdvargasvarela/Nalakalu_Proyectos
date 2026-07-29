# Asociaciones entre proyectos — design

## Contexto

Un proyecto puede necesitar vincularse a otro: una "fase" de diseño que pertenece a una instalación más grande, o un "caso de servicio" (ticket de cambio/rediseño de una pieza) que se abre contra una instalación existente. Ambos casos son la misma idea general — un proyecto de un tipo se asocia a un proyecto de otro tipo, bajo una etiqueta con significado propio — así que se modela como un solo mecanismo genérico y configurable, no como dos conceptos separados.

## Alcance

- **Tipos de asociación configurables** (`ProjectTypeAssociation`): un admin define pares "de tipo X, hacia tipo Y", con una etiqueta libre (ej. "Fase de", "Caso de servicio"). Se administra en una sección propia del admin, `/admin/project_type_associations`, ya que involucra dos tipos de proyecto a la vez (no pertenece naturalmente a la vista de uno solo).
- **Vínculos reales entre proyectos** (`ProjectAssociation`): un proyecto concreto asociado a otro, usando uno de los tipos configurados. Un proyecto puede tener múltiples vínculos del mismo tipo (ej. varios casos de servicio apuntando a la misma instalación).
- **Vista de un proyecto**: tarjeta "Asociaciones" con los vínculos existentes (entrantes y salientes) y dos formas de agregar uno nuevo:
  1. Vincular a un proyecto **ya existente** (admin/gerente, mismo criterio que el resto de tarjetas de gestión del proyecto).
  2. Crear un proyecto **nuevo**, ya vinculado — solo en la dirección "crear el lado chico/nuevo, asociado a un proyecto grande ya existente" (los dos casos reales pedidos: nuevo Caso de Servicio → instalación existente; nueva fase de Diseño → instalación existente). Reusa el formulario normal de "Nuevo proyecto" (sin modal, sin JS nuevo), precargado con el tipo y la asociación — al guardar, vuelve al proyecto original en vez de al nuevo.
- **Permiso nuevo, granular**: cada `ProjectTypeAssociation` tiene un flag `responsables_can_create` — si está tildado, además de admin/gerente (que siempre pueden), un usuario con rol `responsable` que ya está asignado al proyecto existente también puede usar el atajo "crear nuevo y vincular". Vincular a un proyecto **existente** sigue siendo exclusivo de admin/gerente en todos los casos (no cambia).

Fuera de alcance: crear el lado "grande" nuevo a partir del lado "chico" (dirección inversa de la creación rápida — se puede lograr igual vinculando manualmente dos proyectos ya existentes); UI dinámica con JS para acotar el selector de "proyecto existente" por tipo automáticamente (ver Diseño, sección de la tarjeta, para el criterio aceptado); permitir asociaciones donde `from_project_type` y `to_project_type` sean el mismo tipo con ambigüedad de dirección (caso borde, ver Edge cases).

## Diseño

### Modelos

```ruby
# Migración
create_table :project_type_associations do |t|
  t.references :from_project_type, null: false, foreign_key: { to_table: :project_types }
  t.references :to_project_type, null: false, foreign_key: { to_table: :project_types }
  t.string :label, null: false
  t.boolean :responsables_can_create, default: false, null: false
  t.timestamps
end
```

```ruby
# app/models/project_type_association.rb
class ProjectTypeAssociation < ApplicationRecord
  belongs_to :from_project_type, class_name: "ProjectType"
  belongs_to :to_project_type, class_name: "ProjectType"
  has_many :project_associations, dependent: :destroy

  validates :label, presence: true
end
```

```ruby
# Migración
create_table :project_associations do |t|
  t.references :from_project, null: false, foreign_key: { to_table: :projects }
  t.references :to_project, null: false, foreign_key: { to_table: :projects }
  t.references :project_type_association, null: false, foreign_key: true
  t.timestamps
  t.index [:from_project_id, :to_project_id, :project_type_association_id], unique: true, name: "index_project_associations_on_triple"
end
```

```ruby
# app/models/project_association.rb
class ProjectAssociation < ApplicationRecord
  belongs_to :from_project, class_name: "Project"
  belongs_to :to_project, class_name: "Project"
  belongs_to :project_type_association

  validate :projects_match_association_types
  validate :from_and_to_are_different

  private

  def projects_match_association_types
    return if from_project.nil? || to_project.nil? || project_type_association.nil?
    errors.add(:from_project, "debe ser del tipo esperado por la asociación") unless from_project.project_type_id == project_type_association.from_project_type_id
    errors.add(:to_project, "debe ser del tipo esperado por la asociación") unless to_project.project_type_id == project_type_association.to_project_type_id
  end

  def from_and_to_are_different
    errors.add(:to_project, "un proyecto no puede asociarse consigo mismo") if from_project_id.present? && from_project_id == to_project_id
  end
end
```

`Project` gana:

```ruby
has_many :outgoing_project_associations, class_name: "ProjectAssociation", foreign_key: :from_project_id, dependent: :destroy
has_many :incoming_project_associations, class_name: "ProjectAssociation", foreign_key: :to_project_id, dependent: :destroy
```

### Permiso: `User#can_create_associated_project?`

```ruby
def can_create_associated_project?(association, target_project)
  return true if admin? || gerente?
  association.responsables_can_create? && responsable? && can_view_project?(target_project)
end
```

### Admin: `/admin/project_type_associations`

CRUD estándar (`Admin::ProjectTypeAssociationsController`, no anidado — vive al mismo nivel que `resources :responsibles`), formulario con: select "Tipo de origen" (`ProjectType.order(:name)`), select "Tipo de destino", campo de texto "Etiqueta", checkbox "Responsables pueden crear".

### `ProjectsController` — crear un proyecto ya vinculado

`before_action :require_admin_or_gerente!, only: [:new, :create, :bulk_assign_responsible]` se reduce a `only: [:bulk_assign_responsible]`; `:new`/`:create` pasan a un chequeo propio:

```ruby
before_action :authorize_new!, only: [:new, :create]

def authorize_new!
  return if current_user.admin? || current_user.gerente?
  association = ProjectTypeAssociation.find_by(id: params[:project_type_association_id])
  target_project = Project.find_by(id: params[:associate_with_project_id])
  return if association && target_project && current_user.can_create_associated_project?(association, target_project)
  redirect_to projects_path, alert: "No tenés permiso para crear proyectos."
end
```

`new` guarda los dos parámetros de contexto para pasarlos al form:

```ruby
def new
  @project_type = ProjectType.find(params[:project_type_id]) if params[:project_type_id]
  @project = Project.new(project_type: @project_type)
  @project_type_association_id = params[:project_type_association_id]
  @associate_with_project_id = params[:associate_with_project_id]
end
```

`create`, tras guardar, crea el vínculo y redirige al proyecto original si corresponde:

```ruby
def create
  @project = Project.new(project_params)
  @project_type = @project.project_type
  if @project.save
    ProjectAccess.create!(user: current_user, project: @project, can_edit: true) if current_user.gerente?
    if params[:project_type_association_id].present? && params[:associate_with_project_id].present?
      ProjectAssociation.create!(
        from_project: @project, to_project_id: params[:associate_with_project_id],
        project_type_association_id: params[:project_type_association_id]
      )
      redirect_to project_path(params[:associate_with_project_id])
    else
      redirect_to project_path(@project)
    end
  else
    render :new, status: :unprocessable_entity
  end
end
```

`projects/_form.html.erb` agrega, dentro del `form_with`, los dos campos ocultos cuando vienen presentes:

```erb
<%= hidden_field_tag :project_type_association_id, @project_type_association_id if @project_type_association_id.present? %>
<%= hidden_field_tag :associate_with_project_id, @associate_with_project_id if @associate_with_project_id.present? %>
```

### `ProjectAssociationsController` — vincular a un proyecto existente

Nested bajo `projects`, solo `create`/`destroy` (mismo patrón que `project_responsibles`):

```ruby
resources :projects do
  resources :log_entries, only: [:create, :destroy]
  resources :project_responsibles, only: [:create, :destroy]
  resources :project_associations, only: [:create, :destroy]
end
```

```ruby
class ProjectAssociationsController < ApplicationController
  before_action :set_project
  before_action :authorize_edit!

  def create
    association = ProjectTypeAssociation.find(params[:project_association][:project_type_association_id])
    other_id = params[:project_association][:other_project_id]

    pa = if @project.project_type_id == association.from_project_type_id
      ProjectAssociation.new(from_project: @project, to_project_id: other_id, project_type_association: association)
    else
      ProjectAssociation.new(from_project_id: other_id, to_project: @project, project_type_association: association)
    end

    if pa.save
      redirect_to project_path(@project)
    else
      redirect_to project_path(@project), alert: pa.errors.full_messages.to_sentence
    end
  end

  def destroy
    pa = ProjectAssociation.find(params[:id])
    pa.destroy if pa.from_project_id == @project.id || pa.to_project_id == @project.id
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
end
```

### Tarjeta "Asociaciones" en `projects/show.html.erb`

```erb
<% if current_user.can_edit_project?(@project) || ProjectTypeAssociation.where(to_project_type: @project.project_type, responsables_can_create: true).any? { |a| current_user.can_create_associated_project?(a, @project) } %>
  <div class="card mb-4">
    <div class="card-header">Asociaciones</div>
    <div class="card-body">
      <ul class="list-group list-group-flush mb-3">
        <% @project.outgoing_project_associations.includes(:to_project, :project_type_association).each do |pa| %>
          <li class="list-group-item d-flex justify-content-between align-items-center">
            <span>Este proyecto es <strong><%= pa.project_type_association.label %></strong> de <%= link_to pa.to_project.name, project_path(pa.to_project) %></span>
            <% if current_user.can_edit_project?(@project) %>
              <%= button_to "Quitar", project_project_association_path(@project, pa), method: :delete, class: "btn btn-outline-danger btn-sm" %>
            <% end %>
          </li>
        <% end %>
        <% @project.incoming_project_associations.includes(:from_project, :project_type_association).each do |pa| %>
          <li class="list-group-item d-flex justify-content-between align-items-center">
            <span><%= link_to pa.from_project.name, project_path(pa.from_project) %> es <strong><%= pa.project_type_association.label %></strong> de este proyecto</span>
            <% if current_user.can_edit_project?(@project) %>
              <%= button_to "Quitar", project_project_association_path(@project, pa), method: :delete, class: "btn btn-outline-danger btn-sm" %>
            <% end %>
          </li>
        <% end %>
      </ul>

      <% if current_user.can_edit_project?(@project) %>
        <%# ponytail: "Proyecto" lista TODOS los proyectos, sin acotar por tipo vía JS —
            se valida del lado del servidor y se muestra el error si la combinación no
            corresponde al tipo esperado. Suficiente a esta escala; si la lista de
            proyectos crece mucho, esto es candidato a un selector dependiente con JS. %>
        <%= form_with url: project_project_associations_path(@project), method: :post, scope: :project_association, class: "row g-2 mb-3" do |f| %>
          <div class="col-auto">
            <%= f.collection_select :project_type_association_id,
                  ProjectTypeAssociation.where(from_project_type: @project.project_type).or(ProjectTypeAssociation.where(to_project_type: @project.project_type)),
                  :id, :label, { include_blank: "Tipo de asociación" }, class: "form-select" %>
          </div>
          <div class="col-auto">
            <%= f.collection_select :other_project_id, Project.where.not(id: @project.id).order(:name), :id, :name, { include_blank: "Proyecto" }, class: "form-select" %>
          </div>
          <div class="col-auto">
            <%= f.submit "Vincular", class: "btn btn-primary" %>
          </div>
        <% end %>
      <% end %>

      <% ProjectTypeAssociation.where(to_project_type: @project.project_type).each do |association| %>
        <% if current_user.can_create_associated_project?(association, @project) %>
          <%= link_to "+ Nuevo #{association.label}",
                new_project_path(project_type_id: association.from_project_type_id, project_type_association_id: association.id, associate_with_project_id: @project.id),
                class: "btn btn-outline-primary btn-sm" %>
        <% end %>
      <% end %>
    </div>
  </div>
<% end %>
```

## Testing

- `ProjectTypeAssociation`: validaciones (label presente).
- `ProjectAssociation`: válido con tipos correctos; inválido si `from_project`/`to_project` no coinciden con los tipos esperados por la asociación; inválido auto-asociándose; único el triple.
- `User#can_create_associated_project?`: true para admin/gerente siempre; true para un responsable asignado cuando `responsables_can_create` está tildado; false para un responsable sin asignación, o cuando el flag está sin tildar, o para un visor.
- `ProjectsController#new`/`#create`: un responsable con permiso puede llegar al formulario y crear, quedando vinculado y redirigido al proyecto original; uno sin permiso es rechazado; admin/gerente sin contexto de asociación siguen creando proyectos sueltos como siempre.
- `ProjectAssociationsController`: crear un vínculo válido (en ambas direcciones posibles según el tipo del proyecto actual); combinación inválida no crea nada y muestra el error; borrar un vínculo.
- Vista: la tarjeta se muestra a admin/gerente siempre, y a un responsable sin permiso de edición solo si tiene al menos un botón "+ Nuevo" disponible; los vínculos entrantes/salientes se listan con su etiqueta.

## Edge cases

- Una `ProjectTypeAssociation` con `from_project_type == to_project_type` (ej. dos proyectos del mismo tipo asociados entre sí): el código de `ProjectAssociationsController#create` decide la dirección comparando `@project.project_type_id == association.from_project_type_id` — con tipos iguales esa comparación siempre es verdadera, así que `@project` siempre queda del lado `from`. No es ambiguo en la práctica (ambos lados son del mismo tipo, la dirección es solo una etiqueta), pero se documenta como comportamiento fijo, no configurable.
- Borrar un `ProjectType` en uso por una `ProjectTypeAssociation`: la FK lo impediría (`foreign_key: true` sin `dependent`) — coherente con que `ProjectType` ya restringe su borrado si tiene `projects` (`dependent: :restrict_with_error`); acá simplemente fallaría por la FK, sin necesidad de una validación de Rails extra.
- Borrar un `Project` que tiene asociaciones (como origen o destino): cascada vía `dependent: :destroy` en ambos `has_many` de `Project` — no hay restricción, coherente con que borrar proyectos no está bloqueado hoy tampoco por otras relaciones salvo casos puntuales ya existentes.
