# Detalle de proyecto — jerarquía visual y limpieza de duplicados — design

## Contexto

Revisando `projects/show.html.erb` para el pulido de UX encontré dos problemas reales además de la falta de jerarquía visual: (1) hay una tabla pequeña justo antes del Gantt que repite los mismos campos que la sección "Datos" ya lista arriba (ambas muestran los campos marcados `show_in_gantt`, ej. Cliente/Instalador aparecen dos veces en la página); (2) esta página nunca muestra el `status` del proyecto ni tiene botón de archivar — para eso hay que volver a la lista, rompiendo el flujo que ya arreglamos en la Ronda 1.

## Alcance

1. **Header con estado y acciones** — nombre + badge de estado (reusa `status_badge` de la Ronda 2) + tipo, con los botones Editar/Archivar agrupados aparte.
2. **Eliminar la tabla de columnas del Gantt duplicada** — la sección "Datos" ya cubre esos mismos campos.
3. **Tarjetas (`.card`) para "Datos" y "Cronograma"** — el Gantt y la tabla de etapas se combinan en una sola tarjeta "Cronograma" (son la misma idea: el cronograma del proyecto, visual + editable), en vez de dos `<h2>` sueltos.
4. **Botón "Archivar" reutilizable** — se extrae a un partial (`projects/_archive_button`) porque ahora se usa en dos vistas (`index` y `show`) con el mismo markup exacto.

Fuera de alcance: cambios al modelo o al controlador (ninguno de estos cambios requiere lógica nueva — `ProjectsController#update` ya acepta `status` y ya redirige a `project_path`), cambios al Gantt en sí (colores/drag ya resueltos en rondas previas).

## 1. Header

```erb
<div class="d-flex justify-content-between align-items-start mb-3">
  <div>
    <h1 class="d-inline-block me-2 mb-0"><%= @project.name %></h1>
    <%= status_badge(@project.status) %>
    <p class="text-muted mb-0">Tipo: <%= @project.project_type.name %></p>
  </div>
  <div class="d-flex gap-2">
    <%= link_to "Editar", edit_project_path(@project), class: "btn btn-outline-secondary btn-sm" %>
    <%= render "archive_button", project: @project %>
  </div>
</div>
```

## 2. Partial reutilizable para "Archivar"

`app/views/projects/_archive_button.html.erb` (contenido idéntico al que hoy está inline en `index.html.erb` y se agrega aquí en `show.html.erb`):

```erb
<%= form_with(model: project, local: true, method: :patch, style: "display:inline-block") do |f| %>
  <%= f.hidden_field :status, value: "archived" %>
  <%= f.submit "Archivar", class: "btn btn-outline-danger btn-sm" %>
<% end %>
```

`projects/index.html.erb` cambia su bloque inline por `<%= render "archive_button", project: project %>`. Sin cambios de comportamiento — mismo HTML resultante, solo se deja de duplicar.

## 3. Eliminar la tabla duplicada de columnas del Gantt

Se borra por completo este bloque (y la variable `gantt_fields`, que deja de usarse en cualquier otro lugar de la vista):

```erb
<% gantt_fields = @project.project_type.field_definitions.where(show_in_gantt: true).order(:position) %>
<h2>Gantt</h2>

<% if gantt_fields.any? %>
  <table class="table table-sm table-bordered w-auto mb-3">
    ...
  </table>
<% end %>
```

La sección "Datos" (sección 4) ya lista el mismo campo con el mismo valor — no se pierde información, solo la repetición.

## 4. Tarjetas "Datos" y "Cronograma"

```erb
<div class="card mb-4">
  <div class="card-header">Datos</div>
  <ul class="list-group list-group-flush">
    <% @project.project_type.field_definitions.each do |field| %>
      <li class="list-group-item"><strong><%= field.label %>:</strong> <%= @project.custom_fields[field.key] %></li>
    <% end %>
  </ul>
</div>

<div class="card mb-4">
  <div class="card-header">Cronograma</div>
  <div class="card-body">
    <div id="gantt" class="mb-4"></div>
    <%# ...script/style de Gantt sin cambios de lógica, solo de ubicación dentro de la tarjeta... %>

    <%= form_with model: @project do |f| %>
      <table class="table table-sm table-bordered w-auto mb-0">
        ... (sin cambios respecto a la tabla de etapas actual) ...
      <% end %>
      <%= f.submit "Guardar cambios", class: "btn btn-primary" %>
    <% end %>
  </div>
</div>
```

(El `<style>` con los colores por `stage_template_id` y los `<script>` del Gantt no cambian de contenido, solo se mueven dentro de `.card-body` — siguen funcionando igual porque `<style>`/`<script>` no dependen de su posición en el DOM.)

## Testing

- Controlador: `show` — el badge de estado aparece con el texto correcto ("Activo"/"Archivado"); el botón "Archivar" está presente y su `form` apunta a `project_path`; "Editar" sigue presente.
- Controlador: **se reescribe** el test existente `"show renders a Gantt column for each show_in_gantt field, with the project's value shown once"` — ya no hay una tabla de columnas del Gantt que verificar; se reemplaza por una aserción de que el valor del campo aparece **una sola vez** en toda la página (antes aparecía dos veces: en "Datos" y en la tabla duplicada — esta prueba existía justamente para documentar esa duplicación, que ahora se elimina a propósito).
- Controlador: `index` — el botón "Archivar" sigue funcionando igual (ahora vía partial) — los tests existentes de la Ronda 1/2 sobre "Archivar" no deberían necesitar cambios de aserción, solo seguir pasando.
- No hay test automatizado para el aspecto visual de las tarjetas (CSS/Bootstrap, fuera del alcance de Minitest) — se verifica manualmente.

## Edge cases

- Un proyecto sin ningún `custom_fields` value para un campo (`field.key` ausente): la tarjeta "Datos" ya maneja esto hoy (`@project.custom_fields[field.key]` devuelve `nil`, se muestra vacío) — sin cambios de comportamiento.
- Un proyecto sin ninguna etapa (caso ya cubierto en specs previos): la tarjeta "Cronograma" no rompe — el Gantt no dibuja nada y la tabla de etapas no itera filas, igual que hoy.
