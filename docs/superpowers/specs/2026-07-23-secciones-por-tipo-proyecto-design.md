# Secciones por tipo de proyecto (acordeón) en projects#index — design

## Contexto

Ahora hay más de un `ProjectType` (además de "Instalaciones" hay un segundo tipo, "Proyectos", con proyectos "super distintos" entre sí). La pantalla `projects#index` mezcla todos los tipos en una sola tabla y un solo Gantt, lo cual deja de tener sentido cuando los tipos representan cosas muy diferentes (campos, etapas y significado distintos). Se quiere separar la pantalla en secciones — una por tipo de proyecto — en formato acordeón, reutilizando el contenido de cada sección vía un partial.

## Alcance

`projects#index` pasa a mostrar un acordeón de Bootstrap (ya cargado vía CDN, sin JS/dependencias nuevas) con una sección por `ProjectType`. Cada sección es **autónoma**: tiene sus propios filtros (Estado, Instalador, Etapa, Desde/Hasta, Buscar), su propia paginación, su propio Gantt (con filtro de Etapa acotado a las etapas de *ese* tipo) y su propia tabla Listado con asignación masiva. La primera sección arranca expandida; el resto, colapsadas. El filtro "Tipo" desaparece del formulario — ya no hace falta, cada tipo es su propia sección.

Fuera de alcance: `projects#tracker` (Seguimiento) no se toca. No se agrega ninguna dependencia nueva (ni JS ni gemas) — el acordeón es Bootstrap puro.

## Namespacing de parámetros

Cada sección anida sus parámetros de filtro/paginación bajo `sections[<slug>]`, usando el `slug` del `ProjectType` (ej. `sections[instalaciones][status]`, `sections[instalaciones][page]`). Esto evita que el filtro o la paginación de una sección pisen los de otra.

## Diseño

### Controlador

`app/controllers/projects_controller.rb`, `index` pasa a construir un array de "secciones", una por tipo:

```ruby
  def index
    @statuses = Project.distinct.pluck(:status).compact
    @installers = Installer.all
    @sections = ProjectType.all.map { |project_type| build_section(project_type) }
  end
```

Nuevo método privado (reemplaza la lógica que antes vivía directo en `index`, ahora parametrizada por tipo):

```ruby
  def build_section(project_type)
    section_params = params.dig(:sections, project_type.slug) || {}

    projects = Project.where(project_type: project_type).includes(:project_type, project_stages: :stage_template).order(:name)
    projects = section_params[:status].present? ? projects.where(status: section_params[:status]) : projects.where.not(status: "archived")
    if section_params[:installer_id] == "none"
      projects = filter_by_no_installer(projects)
    elsif section_params[:installer_id].present?
      projects = filter_by_installer(projects, section_params[:installer_id])
    end
    projects = filter_by_date_range(projects, section_params[:from_date], section_params[:to_date])
    projects = filter_by_query(projects, section_params[:q])

    projects_list = projects.to_a
    per_page = 20
    page = [section_params[:page].to_i, 1].max
    total_pages = (projects_list.size / per_page.to_f).ceil
    page_projects = projects_list.drop((page - 1) * per_page).first(per_page)
    stage_names = StageTemplate.where(project_type: project_type).order(:name).pluck(:name)

    {
      project_type: project_type,
      params: section_params,
      projects_list: projects_list,
      page_projects: page_projects,
      page: page,
      total_pages: total_pages,
      stage_names: stage_names
    }
  end
```

`filter_by_installer`, `filter_by_no_installer`, `filter_by_date_range`, `filter_by_query` — sin cambios, ya reciben el scope como argumento.

`bulk_assign_installer` — sin cambios: sigue leyendo `params[:installer_id]`/`params[:project_ids]` directo (no anidados), porque el formulario de asignación masiva de cada sección no necesita saber a qué tipo pertenece para actualizar los proyectos elegidos.

### Vista

`app/views/projects/index.html.erb` pasa a ser el acordeón:

```erb
<div class="d-flex justify-content-between align-items-center mb-3">
  <h1 class="mb-0">Proyectos</h1>
  <div class="dropdown">
    <button class="btn btn-primary dropdown-toggle" type="button" data-bs-toggle="dropdown" aria-expanded="false">
      Nuevo proyecto
    </button>
    <ul class="dropdown-menu dropdown-menu-end">
      <% ProjectType.all.each do |project_type| %>
        <li><%= link_to project_type.name, new_project_path(project_type_id: project_type.id), class: "dropdown-item" %></li>
      <% end %>
    </ul>
  </div>
</div>

<div class="accordion" id="projectsAccordion">
  <% @sections.each_with_index do |section, index| %>
    <% slug = section[:project_type].slug %>
    <div class="accordion-item">
      <h2 class="accordion-header">
        <button class="accordion-button <%= "collapsed" unless index == 0 %>" type="button"
                data-bs-toggle="collapse" data-bs-target="#collapse-<%= slug %>">
          <%= section[:project_type].name %> (<%= section[:projects_list].size %>)
        </button>
      </h2>
      <div id="collapse-<%= slug %>" class="accordion-collapse collapse <%= "show" if index == 0 %>"
           data-bs-parent="#projectsAccordion">
        <div class="accordion-body">
          <%= render "project_type_section", section: section %>
        </div>
      </div>
    </div>
  <% end %>
</div>
```

`app/views/projects/_project_type_section.html.erb` (nuevo partial, recibe el local `section`) — es el contenido que hoy vive en `index.html.erb`, con tres cambios de fondo: (1) el `form_with` de filtros usa `scope: "sections[#{slug}]"` para que todos los campos generados por el `form` builder salgan anidados automáticamente; (2) desaparece el campo "Tipo"; (3) todos los ids que deben ser únicos por sección llevan el sufijo `-<%= slug %>`:

```erb
<%
  project_type = section[:project_type]
  slug = project_type.slug
  section_params = section[:params]
%>

<div class="card mb-4">
  <div class="card-body">
    <%= form_with url: projects_path, method: :get, local: true, scope: "sections[#{slug}]", class: "row g-2" do |form| %>
      <div class="col-auto">
        <%= form.label :status, "Estado", class: "form-label" %>
        <%= form.select :status, @statuses.map { |s| [status_label(s), s] },
              { include_blank: "Todos", selected: section_params[:status] }, class: "form-select" %>
      </div>
      <div class="col-auto">
        <%= form.label :installer_id, "Instalador", class: "form-label" %>
        <%= form.select :installer_id,
              [["Sin instalador", "none"]] + @installers.collect { |i| [i.name, i.id] },
              { include_blank: "Todos", selected: section_params[:installer_id] }, class: "form-select" %>
      </div>
      <div class="col-auto">
        <%= form.label :from_date, "Desde", class: "form-label" %>
        <%= form.date_field :from_date, value: section_params[:from_date], class: "form-control" %>
      </div>
      <div class="col-auto">
        <%= form.label :to_date, "Hasta", class: "form-label" %>
        <%= form.date_field :to_date, value: section_params[:to_date], class: "form-control" %>
      </div>
      <div class="col-auto">
        <%= form.label :stage_name, "Etapa", class: "form-label" %>
        <%= form.select :stage_name, section[:stage_names],
              { include_blank: "Todas", selected: section_params[:stage_name] }, class: "form-select" %>
      </div>
      <div class="col-auto">
        <%= form.label :q, "Buscar", class: "form-label" %>
        <%= form.text_field :q, value: section_params[:q], class: "form-control", placeholder: "Nombre, cliente, dirección..." %>
      </div>
      <div class="col-auto align-self-end">
        <%= form.submit "Filtrar", class: "btn btn-primary" %>
      </div>
    <% end %>
  </div>
</div>

<% if section[:projects_list].empty? %>
  <p>No hay proyectos con estos filtros.</p>
<% else %>
  <%
    projects_list = section[:projects_list]
    page_projects = section[:page_projects]
  %>
  <div class="row g-3 mb-4">
    <div class="col-sm-4">
      <div class="card text-center">
        <div class="card-body">
          <div class="display-6"><%= projects_list.size %></div>
          <div class="text-muted">Total</div>
        </div>
      </div>
    </div>
    <div class="col-sm-4">
      <div class="card text-center">
        <div class="card-body">
          <div class="display-6 text-danger"><%= projects_list.count(&:overdue?) %></div>
          <div class="text-muted">Vencidos</div>
        </div>
      </div>
    </div>
    <div class="col-sm-4">
      <div class="card text-center">
        <div class="card-body">
          <div class="display-6 text-success"><%= projects_list.count { |p| p.progress_status == "finalizado" } %></div>
          <div class="text-muted">Finalizados</div>
        </div>
      </div>
    </div>
  </div>

  <% content_for :head do %>
    <link href="https://cdn.jsdelivr.net/npm/frappe-gantt@0.6.1/dist/frappe-gantt.css" rel="stylesheet">
  <% end %>

  <%
    gantt_tasks = projects_list.filter_map do |project|
      if section_params[:stage_name].present?
        stage = project.project_stages.find { |s| s.name == section_params[:stage_name] }
        next if stage.nil?
        stage_start = stage.start_date || project.created_at.to_date
        stage_end = stage.end_date || (stage_start + 7.days)
        first, last = stage_start, stage_end
      else
        first, last = project.gantt_window
      end
      progress_values = project.project_stages.map(&:progress_percent)
      average_progress = progress_values.any? ? (progress_values.sum / progress_values.size.to_f).round : 0
      {
        id: project.id.to_s,
        name: project.name,
        start: first.to_s,
        end: last.to_s,
        progress: average_progress,
        edit_url: project_path(project),
        custom_class: "installer-color-#{project.installer&.id || 'none'}"
      }
    end
    gantt_colors = projects_list.map do |project|
      installer = project.installer
      [installer&.id || "none", installer&.color || "#6c757d"]
    end.uniq
  %>

  <div class="card mb-4">
    <div class="card-header">Cronograma</div>
    <div class="card-body">
      <style>
        .gantt .bar-label {
          font-weight: bold;
        }
        <% gantt_colors.each do |installer_id, color| %>
          .gantt .bar-wrapper.installer-color-<%= installer_id %> .bar,
          .gantt .bar-wrapper.installer-color-<%= installer_id %>:hover .bar,
          .gantt .bar-wrapper.installer-color-<%= installer_id %>.active .bar {
            fill: <%= color %>;
          }
        <% end %>
      </style>

      <div id="gantt-<%= slug %>" class="mb-0" style="max-height: 630px; overflow-y: auto;"></div>

      <script type="application/json" id="gantt-tasks-<%= slug %>"><%== gantt_tasks.to_json %></script>

      <script src="https://cdn.jsdelivr.net/npm/frappe-gantt@0.6.1/dist/frappe-gantt.min.js"></script>
      <script>
        document.addEventListener("DOMContentLoaded", function () {
          var tasks = JSON.parse(document.getElementById("gantt-tasks-<%= slug %>").textContent);
          if (tasks.length > 0) {
            var gantt = new Gantt("#gantt-<%= slug %>", tasks, {
              language: "es",
              on_click: function (task) { window.location = task.edit_url; },
              on_date_change: function () { gantt.refresh(tasks); },
              on_progress_change: function () { gantt.refresh(tasks); }
            });
          }
        });
      </script>
    </div>
  </div>

  <%= form_with url: bulk_assign_installer_projects_path(request.query_parameters), method: :patch, local: true,
        id: "bulk-assign-form-#{slug}", class: "d-flex gap-2 align-items-end mb-3" do |f| %>
    <div>
      <%= f.label :installer_id, "Asignar instalador a los seleccionados", for: "bulk-assign-installer-select-#{slug}", class: "form-label" %>
      <%= f.select :installer_id, @installers.collect { |i| [i.name, i.id] },
            { include_blank: "Elegí un instalador" }, class: "form-select", id: "bulk-assign-installer-select-#{slug}" %>
    </div>
    <%= f.submit "Asignar", class: "btn btn-primary" %>
  <% end %>

  <div class="card mb-4">
    <div class="card-header">Listado</div>
    <div class="card-body p-0">
      <table class="table table-striped mb-0">
        <thead>
          <tr>
            <th><input type="checkbox" id="select-all-projects-<%= slug %>"></th>
            <th>Nombre</th><th>Estado</th><th>Avance</th><th></th>
          </tr>
        </thead>
        <tbody>
          <% page_projects.each do |project| %>
            <tr>
              <td><%= check_box_tag "project_ids[]", project.id, false, id: nil, form: "bulk-assign-form-#{slug}" %></td>
              <td><%= link_to project.name, project_path(project) %></td>
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
      <% if section[:total_pages] > 1 %>
        <nav class="p-3">
          <ul class="pagination mb-0">
            <li class="page-item <%= "disabled" if section[:page] <= 1 %>">
              <%= link_to "Anterior", projects_path(request.query_parameters.deep_merge("sections" => { slug => { "page" => section[:page] - 1 } })), class: "page-link" %>
            </li>
            <% (1..section[:total_pages]).each do |n| %>
              <li class="page-item <%= "active" if n == section[:page] %>">
                <%= link_to n, projects_path(request.query_parameters.deep_merge("sections" => { slug => { "page" => n } })), class: "page-link" %>
              </li>
            <% end %>
            <li class="page-item <%= "disabled" if section[:page] >= section[:total_pages] %>">
              <%= link_to "Siguiente", projects_path(request.query_parameters.deep_merge("sections" => { slug => { "page" => section[:page] + 1 } })), class: "page-link" %>
            </li>
          </ul>
        </nav>
      <% end %>
    </div>
  </div>

  <script>
    document.getElementById("select-all-projects-<%= slug %>").addEventListener("change", function (e) {
      document.querySelectorAll('input[form="bulk-assign-form-<%= slug %>"]').forEach(function (cb) { cb.checked = e.target.checked; });
    });
  </script>
<% end %>
```

Nota: la columna "Tipo" de la tabla Listado desaparece (redundante ahora — toda la tabla es de un solo tipo, dado por la sección).

`request.query_parameters.deep_merge(...)` (no `.merge`) es necesario para que cambiar la página de una sección no borre los filtros/página de las demás secciones — un `.merge` superficial reemplazaría toda la clave `"sections"` completa.

## Testing

- Controlador: `index` con 2 `ProjectType`s — cada sección solo lista los proyectos de su propio tipo.
- Controlador: filtrar por Estado/Instalador/Etapa/Desde-Hasta/Buscar dentro de `sections[<slug>][...]` afecta solo esa sección, no las demás.
- Controlador: paginar una sección (`sections[<slug>][page]=2`) no afecta la paginación de otra sección.
- Vista: el acordeón renderiza un `.accordion-item` por tipo, con la primera sección expandida (`show`) y las demás colapsadas.
- Vista: los ids (`gantt-<slug>`, `bulk-assign-form-<slug>`, `select-all-projects-<slug>`) son únicos por sección, sin colisiones.
- Vista: el desplegable "Etapa" de cada sección solo lista las etapas de *ese* tipo de proyecto.

## Edge cases

- Enviar el formulario de filtros de una sección resetea la página/filtros previamente elegidos en las **demás** secciones (porque cada `<form>` de filtro solo envía sus propios campos, reemplazando toda la query string) — se acepta como limitación conocida, dado que las secciones son independientes y normalmente se interactúa con una a la vez (acordeón). Los links de paginación (que sí usan `deep_merge` sobre la query string completa) no tienen este problema.
- Un `ProjectType` sin ningún proyecto: su sección muestra "No hay proyectos con estos filtros." igual que hoy, sin romper el acordeón.
- Un `ProjectType` sin ningún `StageTemplate` configurado: su desplegable "Etapa" queda vacío salvo "Todas" — no rompe nada, el filtro de etapa simplemente no tiene opciones útiles para ese tipo.
