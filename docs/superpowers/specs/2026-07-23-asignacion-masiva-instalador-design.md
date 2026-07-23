# Filtro "Sin instalador" + asignación masiva de instalador — design

## Contexto

Después de importar proyectos en bloque (Ronda 12) es común que queden varios sin instalador asignado — hoy solo se puede asignar uno por uno, editando cada proyecto. Se agrega: (1) una opción "Sin instalador" al filtro existente, para encontrarlos rápido, y (2) checkboxes en la tabla de la pantalla de inicio + un selector para asignar el mismo instalador a todos los seleccionados de una vez.

## Alcance

1. **Filtro "Sin instalador"** — nueva opción en el `<select>` de Instalador ya existente (`projects#index`), valor especial `"none"`.
2. **Checkboxes + asignación masiva** en la tabla "Listado" de `projects#index` — una casilla por fila + "seleccionar todos", un `<select>` de instalador y un botón "Asignar" que actualiza el campo de instalador de todos los proyectos marcados.
3. **`ProjectsController#bulk_assign_installer`** — nueva acción, recibe los ids de proyecto seleccionados + el instalador elegido, actualiza el campo `reference` correspondiente de cada proyecto (según el campo de su propio `project_type` que apunte a `installers` — sin asumir que siempre se llama `"instalador"`, mismo principio ya usado en `filter_by_installer`/`Project#installer`).

Fuera de alcance: asignación masiva de otros campos (solo instalador, que es lo pedido), deshacer una asignación masiva (se puede corregir editando cada proyecto o repitiendo la asignación masiva con otro instalador), aplicar esto en Seguimiento (esa pantalla ya tiene su propio flujo de edición por proyecto, esta acción es específica de la lista de Proyectos).

## 1. Filtro "Sin instalador"

`app/controllers/projects_controller.rb`:

```ruby
def index
  @project_types = ProjectType.all
  @statuses = Project.distinct.pluck(:status).compact
  @installers = Installer.all
  @projects = Project.includes(:project_type, project_stages: :stage_template)
  @projects = params[:status].present? ? @projects.where(status: params[:status]) : @projects.where.not(status: "archived")
  @projects = @projects.where(project_type_id: params[:project_type_id]) if params[:project_type_id].present?
  if params[:installer_id] == "none"
    @projects = filter_by_no_installer(@projects)
  elsif params[:installer_id].present?
    @projects = filter_by_installer(@projects, params[:installer_id])
  end
end
```

Nuevo método privado, junto a `filter_by_installer`:

```ruby
def filter_by_no_installer(scope)
  keys = FieldDefinition.where(reference_table: "installers").distinct.pluck(:key)
  return scope if keys.empty?
  keys.reduce(scope) { |s, key| s.where("custom_fields ->> ? IS NULL OR custom_fields ->> ? = ''", key, key) }
end
```

Vista — el `<select>` de Instalador agrega la opción antes de la lista de instaladores:

```erb
<%= form.select :installer_id,
      [["Sin instalador", "none"]] + @installers.collect { |i| [i.name, i.id] },
      { include_blank: "Todos", selected: params[:installer_id] }, class: "form-select" %>
```

## 2 y 3. Asignación masiva

Ruta (antes de `resources :projects`, mismo motivo que otras rutas con segmento literal en este archivo — evitar que `resources :projects` la capture como `/projects/:id`):

```ruby
patch "projects/bulk_assign_installer", to: "projects#bulk_assign_installer", as: :bulk_assign_installer_projects
```

`ProjectsController#bulk_assign_installer`:

```ruby
def bulk_assign_installer
  if params[:installer_id].blank? || Array(params[:project_ids]).empty?
    redirect_to projects_path(request.query_parameters), alert: "Elegí un instalador y al menos un proyecto." and return
  end

  count = 0
  Project.where(id: params[:project_ids]).find_each do |project|
    key = project.project_type.field_definitions.find_by(reference_table: "installers")&.key
    next unless key

    project.custom_fields = project.custom_fields.merge(key => params[:installer_id])
    count += 1 if project.save
  end

  redirect_to projects_path(request.query_parameters), notice: "Instalador asignado a #{count} proyecto(s)."
end
```

(Un proyecto cuyo `project_type` no tiene ningún campo `reference_table: "installers"` simplemente se salta — no hay dónde guardar el instalador para ese tipo, no es un error. `redirect_to projects_path(request.query_parameters)` vuelve a la lista con los mismos filtros que tenía el usuario antes de la acción, no a la lista sin filtrar.)

`app/views/projects/index.html.erb` — el formulario de asignación masiva va **antes** de la tabla, no envolviéndola (un `<form>` no puede contener otro `<form>` — el botón "Archivar" de cada fila ya es su propio `form_with` vía `_archive_button`, y anidarlos rompería el HTML). En vez de envolver la tabla, cada checkbox se asocia al formulario grande a distancia usando el atributo HTML5 `form="..."`, que vincula un campo con un `<form>` en cualquier parte del documento sin necesidad de que sea su descendiente:

```erb
<%= form_with url: bulk_assign_installer_projects_path, method: :patch, local: true, id: "bulk-assign-form", class: "d-flex gap-2 align-items-end mb-3" do |f| %>
  <div>
    <%= f.label :installer_id, "Asignar instalador a los seleccionados", class: "form-label" %>
    <%= f.select :installer_id, @installers.collect { |i| [i.name, i.id] }, { include_blank: "Elegí un instalador" }, class: "form-select" %>
  </div>
  <%= f.submit "Asignar", class: "btn btn-primary" %>
<% end %>

<div class="card mb-4">
  <div class="card-header">Listado</div>
  <div class="card-body p-0">
    <table class="table table-striped mb-0">
      <thead>
        <tr>
          <th><input type="checkbox" id="select-all-projects"></th>
          <th>Nombre</th><th>Tipo</th><th>Estado</th><th>Avance</th><th></th>
        </tr>
      </thead>
      <tbody>
        <% projects_list.each do |project| %>
          <tr>
            <td><%= check_box_tag "project_ids[]", project.id, false, id: nil, form: "bulk-assign-form" %></td>
            <td><%= link_to project.name, project_path(project) %></td>
            <td><%= project.project_type.name %></td>
            <td><%= status_badge(project.status) %></td>
            <td>
              <%= progress_status_badge(project.progress_status) %>
              <%= overdue_badge if project.overdue? %>
            </td>
            <td>
              <%= link_to "Editar", edit_project_path(project), class: "btn btn-outline-secondary btn-sm" %>
              <%= render "archive_button", project: project %>
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
  </div>
</div>

<script>
  document.getElementById("select-all-projects").addEventListener("change", function (e) {
    document.querySelectorAll('input[name="project_ids[]"]').forEach(function (cb) { cb.checked = e.target.checked; });
  });
</script>
```

(El formulario grande y el de cada `_archive_button` quedan como hermanos en el DOM, ninguno anidado dentro del otro — el atributo `form="bulk-assign-form"` en cada checkbox es lo que los conecta con el `<select>`/botón "Asignar" de arriba, sin que la tabla necesite estar dentro de ese `<form>`.)

## Testing

- Controlador: `index` con `installer_id=none` — muestra solo proyectos sin instalador asignado.
- Controlador: `bulk_assign_installer` — asigna el instalador a todos los proyectos seleccionados, cuenta correcta en el mensaje.
- Controlador: `bulk_assign_installer` sin instalador elegido o sin proyectos seleccionados — no rompe, redirige con una alerta.
- Controlador: `bulk_assign_installer` con un proyecto de un tipo sin campo de instalador — se salta sin error, no afecta el conteo de los demás.
- Controlador: la tabla renderiza un checkbox por proyecto con el `name` correcto (`project_ids[]`).

## Edge cases

- Ningún proyecto seleccionado pero sí instalador elegido (o viceversa): se trata igual — mensaje de alerta, no se asigna nada.
- Todos los proyectos ya tienen instalador: la asignación masiva simplemente los sobrescribe con el nuevo instalador elegido (no hay una casilla "no sobrescribir los que ya tienen" — no fue pedido, y el usuario ve qué instalador tiene cada uno antes de seleccionar filas gracias al filtro "Sin instalador").
