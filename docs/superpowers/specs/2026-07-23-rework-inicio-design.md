# Rework de la página de inicio (Proyectos) — design

## Contexto

`projects#index` (la pantalla de inicio) es la única vista de proyectos que **no** muestra los badges de avance/vencido construidos en la ronda anterior, no tiene ningún resumen numérico, y el Gantt/tabla flotan sin tarjetas (inconsistente con el resto de la app). "Nuevo proyecto" es una lista suelta al final de la página en vez de estar integrada con el título.

Nota técnica importante encontrada durante el diseño: la app carga el CSS de Bootstrap pero no su JS (`app/views/layouts/application.html.erb` solo tiene el `<link>`, nunca un `<script>` del bundle) — el mismo problema de fondo que ya causó bugs reales antes (los links de Turbo rotos). Un dropdown de Bootstrap (`data-bs-toggle="dropdown"`) no funcionaría sin ese JS. Se agrega el bundle de Bootstrap al layout como parte de este cambio.

## Alcance

1. **Bootstrap JS bundle** en el layout — habilita dropdowns (y cualquier otro componente interactivo de Bootstrap) en toda la app de una vez.
2. **KPIs arriba** — tres tarjetas: Total, Vencidos, Finalizados, calculadas sobre los proyectos actualmente filtrados (`@projects`, el mismo conjunto que se muestra abajo — no un conteo global aparte).
3. **Filtros en tarjeta**.
4. **Gantt en tarjeta** (mismo patrón que "Cronograma" en el detalle de proyecto).
5. **Tabla en tarjeta**, con una columna "Avance" nueva (badges de `progress_status`/`overdue?`, los mismos ya usados en el resto de la app).
6. **"Nuevo proyecto" como botón con dropdown**, junto al título, en vez de la lista suelta al final (que se elimina).

Fuera de alcance: cambiar el mecanismo de filtrado (`ProjectsController#index` no cambia su lógica de query, solo la vista consume los mismos `@projects`), agregar más KPIs de los tres acordados, tocar `projects#show`/`tracker` (ya tienen su propio pulido de rondas anteriores).

## 1. Bootstrap JS bundle

`app/views/layouts/application.html.erb`, antes de `</body>`:

```erb
<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js"></script>
```

(Mismo CDN/versión ya usada para el CSS — no es una dependencia nueva, es la mitad que faltaba de una que ya está en uso.)

## 2-6. `projects/index.html.erb`

Estructura completa:

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

<div class="card mb-4">
  <div class="card-body">
    <%= form_with url: projects_path, method: :get, local: true, class: "row g-2" do |form| %>
      <%# ... mismos 3 <select> (Tipo/Estado/Instalador) + submit "Filtrar" que ya existen, sin cambios ... %>
    <% end %>
  </div>
</div>

<% if @projects.none? %>
  <p>No hay proyectos con estos filtros.</p>
<% else %>
  <%
    projects_list = @projects.to_a
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

  <%# ... gantt_tasks/gantt_colors se calculan desde `projects_list` en vez de `@projects.map`, sin otro cambio de lógica ... %>

  <div class="card mb-4">
    <div class="card-header">Cronograma general</div>
    <div class="card-body">
      <%# <style> + <div id="gantt"> + los dos <script> existentes, sin cambios de comportamiento %>
    </div>
  </div>

  <div class="card mb-4">
    <div class="card-header">Listado</div>
    <div class="card-body p-0">
      <table class="table table-striped mb-0">
        <thead>
          <tr><th>Nombre</th><th>Tipo</th><th>Estado</th><th>Avance</th><th></th></tr>
        </thead>
        <tbody>
          <% projects_list.each do |project| %>
            <tr>
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
<% end %>
```

Se elimina por completo la sección final `<h2>Nuevo proyecto</h2><ul>...</ul>` — reemplazada por el dropdown del encabezado.

## Testing

- Controlador: `index` — el dropdown "Nuevo proyecto" contiene un link por cada `ProjectType`.
- Controlador: `index` — las tres tarjetas KPI muestran los números correctos (Total = cantidad de `@projects`, Vencidos = cantidad con `overdue?`, Finalizados = cantidad con `progress_status == "finalizado"`).
- Controlador: `index` — la tabla muestra la columna "Avance" con los badges correctos por proyecto.
- Controlador: `index` — Gantt y tabla están dentro de tarjetas (`.card .card-header`).
- Se retira cualquier test que dependiera de la lista `<h2>Nuevo proyecto</h2>` al final (no existe ninguno actualmente, confirmado por grep).

## Edge cases

- `@projects.none?` (sin resultados con los filtros aplicados): se mantiene el mensaje simple, sin KPIs/Gantt/tabla — igual que hoy.
- Todos los proyectos filtrados sin instalador asignado, o todos vencidos, etc.: los conteos simplemente dan 0 en la tarjeta correspondiente, sin romper (mismo patrón ya usado por `Array#count`).
