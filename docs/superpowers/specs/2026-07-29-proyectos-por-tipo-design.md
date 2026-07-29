# Proyectos por tipo (navegación en pestañas) — design

## Contexto

`projects#index` (`/projects`, la pantalla "Proyectos") arma hoy un `accordion` con **una sección por cada `ProjectType`** (`@sections = ProjectType.all.map { |pt| build_section(pt) }`), cada una con su propio Gantt, filtros y listado paginado. Visualmente colapsa a una sola sección abierta, pero el controlador calcula filtros, Gantt y paginado de **todos** los tipos en cada request, sin importar cuál está expandido — con 2 tipos hoy no se nota, pero escala mal a medida que se agreguen más.

Este documento cubre solo la reestructuración de navegación/carga de `projects#index`. El pulido visual general de la app queda para una segunda vuelta, spec aparte.

## Alcance

- `projects#index` pasa a mostrar **un solo `ProjectType` por request**, elegido por un segmento de URL (`/projects/tipo/:slug`), con pestañas arriba para cambiar entre tipos — cada pestaña tiene su propia URL, bookmarkeable y compatible con atrás/adelante del navegador.
- `root_path` (`/`) redirige a la pestaña del primer `ProjectType` (orden actual de `ProjectType.all`, sin campo de posición propio — no se agrega uno, fuera de alcance).
- Los filtros (estado, tipo de responsable, responsable, fechas, etapa, búsqueda, página) pasan de params anidados por slug (`sections[slug][...]`) a params planos, ya que ahora hay una sola sección por página.
- El botón "Nuevo proyecto" deja de ser un dropdown con un tipo por opción — pasa a ser un botón directo que crea un proyecto del tipo de la pestaña actual.
- `/projects/seguimiento` (tracker) **no se toca** — ya resuelve el mismo problema con su propio dropdown de tipo, y el usuario prefirió no unificarlo con pestañas.
- Ningún cambio de modelo, migración, ni de comportamiento de negocio (filtros, Gantt, asignación masiva, permisos) — es puramente de ruteo/vista/controlador.

Fuera de alcance: pulido visual general (tipografía, espaciado, colores) — spec aparte; unificar `tracker` con el mismo esquema de pestañas; agregar un campo de orden explícito a `ProjectType`.

## Diseño

### Ruta

```ruby
get "projects/tipo/:slug", to: "projects#index", as: :project_type_projects
```

El segmento literal `tipo` evita cualquier ambigüedad con `/projects/:id` (`show`) de `resources :projects`, sin necesidad de constraints numéricos.

### `ProjectsController#index`

```ruby
def index
  @project_type = ProjectType.find_by(slug: params[:slug]) || ProjectType.first
  return redirect_to(root_path) if @project_type.nil?
  return redirect_to(project_type_projects_path(@project_type.slug)) if params[:slug].blank?

  @project_types = ProjectType.all
  @statuses = Project.distinct.pluck(:status).compact
  @section = build_section(@project_type)
end
```

- Sin `ProjectType` configurado: redirige a `root_path` (que a su vez cae en este mismo `index` sin loop, ya que `@project_type` sigue siendo `nil` y la vista muestra el mensaje ya existente "No hay tipos de proyecto configurados todavía" — se agrega ese `if @project_type.nil?` a la vista, análogo al de `tracker.html.erb`).
- Slug inexistente en la URL (`ProjectType.find_by(slug: params[:slug])` devuelve `nil` pero hay otros tipos): cae a `ProjectType.first` y redirige a su URL canónica, mismo criterio que "sin slug".

### `build_section` — de params anidados a planos

```ruby
def build_section(project_type)
  projects = Project.visible_to(current_user).where(project_type: project_type).includes(:project_type, project_stages: :stage_template).order(:name)
  projects = params[:status].present? ? projects.where(status: params[:status]) : projects.where.not(status: "archived")
  projects = filter_by_responsible(projects, params[:responsible_type_id], params[:responsible_id])
  projects = filter_by_date_range(projects, params[:from_date], params[:to_date])
  projects = filter_by_query(projects, params[:q])

  projects_list = projects.to_a
  per_page = 20
  page = [params[:page].to_i, 1].max
  total_pages = (projects_list.size / per_page.to_f).ceil
  page_projects = projects_list.drop((page - 1) * per_page).first(per_page)
  stage_names = StageTemplate.where(project_type: project_type).order(:name).pluck(:name)

  stage_name = if params[:stage_name].present?
    params[:stage_name]
  elsif params.key?(:sections_seen) # ver nota abajo
    nil
  else
    project_type.stage_templates.find_by(default_in_filter: true)&.name
  end

  {
    project_type: project_type,
    params: params.slice(:status, :responsible_type_id, :responsible_id, :from_date, :to_date, :stage_name, :q, :page),
    stage_name: stage_name,
    projects_list: projects_list,
    page_projects: page_projects,
    page: page,
    total_pages: total_pages,
    stage_names: stage_names
  }
end
```

Nota sobre `stage_name` por defecto: la versión actual distingue "la sección nunca se filtró" (usa la etapa marcada `default_in_filter`) de "se filtró explícitamente y se dejó en blanco" (`section_submitted.nil?` vs. `section_params[:stage_name]` vacío), algo que con params anidados por slug se resolvía viendo si la key `sections[slug]` estaba presente en absoluto. Con params planos ya no hay una key de sección para chequear — el plan de implementación resuelve esto con el patrón estándar de Rails para "parámetro presente pero vacío" vs. "parámetro ausente": `params.key?(:stage_name)` (presente, incluso vacío, tras enviar el form con "Todas" seleccionado) vs. ausencia total del parámetro (primera carga de la página, sin query string). El pseudocódigo de arriba simplifica esto — el plan de implementación escribe la condición exacta.

### Vista `projects/index.html.erb`

```erb
<div class="d-flex justify-content-between align-items-center mb-3">
  <h1 class="mb-0">Proyectos</h1>
  <% if @project_type && (current_user.admin? || current_user.gerente?) %>
    <%= link_to "Nuevo proyecto", new_project_path(project_type_id: @project_type.id), class: "btn btn-primary" %>
  <% end %>
</div>

<% if @project_type.nil? %>
  <p>No hay tipos de proyecto configurados todavía.</p>
<% else %>
  <ul class="nav nav-tabs mb-4">
    <% @project_types.each do |project_type| %>
      <li class="nav-item">
        <%= link_to project_type.name, project_type_projects_path(project_type.slug),
              class: "nav-link #{"active" if project_type == @project_type}" %>
      </li>
    <% end %>
  </ul>

  <%= render "project_type_section", section: @section %>
<% end %>
```

### `_project_type_section.html.erb`

- El `form_with` de filtros pierde `scope: "sections[#{slug}]"` — los campos pasan a nombrarse `status`, `responsible_type_id`, etc. directamente (sin el prefijo `sections[slug]`).
- El link "Quitar filtros" pasa de reconstruir `request.query_parameters.deep_merge("sections" => {...})` a simplemente `project_type_projects_path(slug)` sin query string (limpiar filtros = volver a la URL base de la pestaña).
- El formulario de asignación masiva (`bulk_assign_responsible_projects_path`) sigue mandando `responsible_type_id`/`responsible_id` sueltos como ya hace — sin cambios ahí más que quitar cualquier referencia a `sections[slug]` que hubiera en la reconstrucción de query params del submit del filtro (no la tiene, es un form action propio).
- Los `id` de elementos del DOM sufijados con `slug` (`#gantt-<%= slug %>`, `#bulk-assign-form-<%= slug %>`, checkboxes, etc.) **se mantienen igual** (aunque ya no hace falta distinguir entre secciones) para minimizar el diff sobre el JS inline existente.

### Tests

- `test/controllers/projects_controller_test.rb`: todo test que hoy hace `get projects_path, params: { sections: { slug => {...} } }` pasa a `get project_type_projects_path(slug), params: {...}` (params planos). Se agregan casos para: `/projects` sin slug redirige a la pestaña del primer tipo; un slug que no matchea ningún `ProjectType` redirige igual que "sin slug"; sin `ProjectType` configurado en absoluto, `/projects` no rompe (mensaje "No hay tipos de proyecto configurados todavía", sin loop de redirect).
- Ningún test de modelo cambia (no hay cambios de modelo).

## Edge cases

- Un solo `ProjectType` configurado: la barra de pestañas muestra una sola pestaña (siempre activa) — no se oculta la barra en ese caso, es un estado válido y simple de dejar así (no vale la pena una condición extra para ocultarla con un solo tipo).
- Cambiar de pestaña resetea los filtros de la pestaña anterior (cada pestaña es una URL distinta sin query string) — comportamiento esperado, coherente con que cada tipo es su propia página ahora.
- Un `ProjectType` sin proyectos: la pestaña se muestra igual (permite crear el primer proyecto de ese tipo desde ahí), el contenido de la sección muestra "No hay proyectos con estos filtros" como ya hace hoy cuando la lista queda vacía.
