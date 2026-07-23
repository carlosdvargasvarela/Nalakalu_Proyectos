# Pantalla "Seguimiento" — edición en bloque de etapas por tipo de proyecto — design

## Contexto

El pedido original que motivó esta app era el Excel de seguimiento de instalaciones: una hoja con un bloque por pedido, cada uno con sus subprocesos (TAREA/INICIO/FIN/PROGRESO) editables ahí mismo. Hoy la app cubre esto proyecto por proyecto (`projects#show`), pero no hay una vista donde se vean/editen los subprocesos de *varios* proyectos del mismo tipo a la vez — hay que entrar uno por uno. Esta pantalla nueva ("Seguimiento") cierra ese hueco reutilizando exactamente el bloque "Cronograma" (tabla de etapas editable) que ya existe en `projects#show`, repetido una vez por cada proyecto del tipo elegido.

## Alcance

1. **Pantalla nueva `/projects/seguimiento`** con su propio link de navegación, separada de "Proyectos" (que sigue siendo la lista + Gantt + alta).
2. **Selector de tipo de proyecto** arriba — obligatorio conceptualmente (los campos a mostrar dependen del tipo), con el primer tipo existente como default para que la pantalla nunca se vea vacía al entrar.
3. **Un bloque por proyecto** del tipo elegido (no archivado): encabezado con nombre + link al detalle completo + los campos marcados `show_in_gantt` de ese tipo (hoy Cliente e Instalador), seguido de su propia tabla de etapas editable (Etapa/Inicio/Fin/% Avance) con su propio botón "Guardar".

Fuera de alcance (decidido en brainstorming): un solo botón "Guardar todo" (cada proyecto guarda por separado, reutilizando `accepts_nested_attributes_for` ya existente — cero endpoint nuevo), Gantt visual por proyecto en esta pantalla (sería demasiados gráficos cargando a la vez; cada bloque enlaza al detalle completo si se quiere ver el Gantt), edición de los campos `show_in_gantt` mostrados como encabezado (son de solo lectura aquí, se editan en `projects#edit` como ya existe).

## 1. Ruta

```ruby
get "projects/seguimiento", to: "projects#tracker", as: :tracker_projects
resources :projects
```

(Antes de `resources :projects`, mismo motivo que la ruta `dashboard` que existió en una ronda anterior: evitar que `resources :projects` capture `/projects/seguimiento` como si fuera `/projects/:id`.)

## 2. Controlador

`ProjectsController#tracker` (acción nueva):

```ruby
def tracker
  @project_types = ProjectType.all
  @project_type = ProjectType.find_by(id: params[:project_type_id]) || ProjectType.first
  @projects = @project_type ? Project.where(project_type: @project_type).where.not(status: "archived").includes(project_stages: :stage_template).order(:name) : Project.none
end
```

(Si no hay ningún `ProjectType` creado todavía — caso borde, la app siempre siembra "Instalaciones" pero en teoría podría borrarse todo desde el admin —, `@project_type` es `nil` y `@projects` es `Project.none`; la vista muestra un mensaje en vez de romper.)

## 3. Vista

`app/views/projects/tracker.html.erb`:

```erb
<h1>Seguimiento</h1>

<%= form_with url: tracker_projects_path, method: :get, local: true, class: "row g-2 mb-4" do |form| %>
  <div class="col-auto">
    <%= form.label :project_type_id, "Tipo", class: "form-label" %>
    <%= form.select :project_type_id, @project_types.collect { |pt| [pt.name, pt.id] },
          { selected: @project_type&.id }, class: "form-select" %>
  </div>
  <div class="col-auto align-self-end">
    <%= form.submit "Ver", class: "btn btn-primary" %>
  </div>
<% end %>

<% if @project_type.nil? %>
  <p>No hay tipos de proyecto configurados todavía.</p>
<% elsif @projects.none? %>
  <p>No hay proyectos de este tipo.</p>
<% else %>
  <% gantt_fields = @project_type.field_definitions.where(show_in_gantt: true).order(:position) %>
  <% @projects.each do |project| %>
    <div class="card mb-4">
      <div class="card-header d-flex justify-content-between align-items-center">
        <div>
          <%= link_to project.name, project_path(project), class: "fw-bold text-decoration-none" %>
          <% gantt_fields.each do |field| %>
            <span class="text-muted ms-3"><%= field.label %>: <%= project.custom_fields[field.key] %></span>
          <% end %>
        </div>
        <%= status_badge(project.status) %>
      </div>
      <div class="card-body">
        <%= form_with model: project do |f| %>
          <table class="table table-sm table-bordered w-auto mb-0">
            <thead>
              <tr><th>Etapa</th><th>Inicio</th><th>Fin</th><th>% Avance</th></tr>
            </thead>
            <tbody>
              <%= f.fields_for :project_stages, project.project_stages.includes(:stage_template).order(:id) do |sf| %>
                <tr>
                  <td><%= sf.object.name %></td>
                  <td><%= sf.hidden_field :id %><%= sf.date_field :start_date, class: "form-control form-control-sm" %></td>
                  <td><%= sf.date_field :end_date, class: "form-control form-control-sm" %></td>
                  <td><%= sf.number_field :progress_percent, min: 0, max: 100, class: "form-control form-control-sm" %></td>
                </tr>
              <% end %>
            </tbody>
          </table>
          <%= f.submit "Guardar", class: "btn btn-primary btn-sm mt-3" %>
        <% end %>
      </div>
    </div>
  <% end %>
<% end %>
```

(Cada bloque es exactamente el mismo mecanismo que `projects#show`'s tabla de etapas — mismo `f.fields_for :project_stages`, mismo `accepts_nested_attributes_for` del modelo, mismo `ProjectsController#update`. Sin Gantt/JS de arrastre aquí — no se pidió y evita cargar N instancias de `frappe-gantt` en una sola página. Sin `id="stage-..."` en las filas — ese id solo servía para el `on_click`/scroll del Gantt, que no existe en esta vista.)

## 4. Nav

`app/views/layouts/_navbar.html.erb` agrega un link "Seguimiento" → `tracker_projects_path`, junto a "Proyectos".

## Testing

- Controlador: `tracker` sin `project_type_id` — usa el primer `ProjectType` por defecto.
- Controlador: `tracker` con `project_type_id` explícito — filtra correctamente.
- Controlador: cada proyecto del tipo aparece con su propio bloque, sus campos `show_in_gantt` como encabezado, y una tabla con una fila por etapa.
- Controlador: proyectos archivados no aparecen (mismo criterio que `projects#index`).
- Controlador: guardar la tabla de un proyecto específico actualiza solo ese proyecto (reusa el test ya existente de `project_stages_attributes`, aquí se agrega uno equivalente vía esta ruta/vista si el flujo de guardado difiere — no debería, es el mismo `ProjectsController#update`).
- Controlador: caso sin ningún `ProjectType` — muestra el mensaje en vez de romper (se fuerza en el test borrando todos los `ProjectType` de prueba, si los fixtures lo permiten, o se documenta como no cubierto si los fixtures siempre traen uno).
- Controlador: `NavbarTest` — el link "Seguimiento" está presente.

## Edge cases

- Un proyecto sin ninguna etapa (caso ya cubierto en specs previos): su bloque muestra una tabla vacía, sin romper.
- Dos proyectos del mismo tipo con nombres iguales: cada uno tiene su propio bloque/formulario independiente (el id del proyecto en el form los distingue, no el nombre).
- Cambiar el tipo de proyecto seleccionado en el `<select>` sin haber guardado cambios pendientes en la tabla de abajo: al enviar el filtro (`method: :get`) se recarga toda la página — cualquier cambio no guardado en las tablas se pierde, igual que pasaría al navegar a cualquier otra página sin guardar (comportamiento esperado, no se agrega advertencia de "cambios sin guardar" — no se pidió).
