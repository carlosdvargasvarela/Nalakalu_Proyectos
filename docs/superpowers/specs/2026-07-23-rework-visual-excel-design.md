# Acercar el UI al Excel original — franja de proyecto + tabla de etapas compartida — design

## Contexto

El Excel original (la referencia de todo este proyecto) muestra cada pedido como una franja de color horizontal con sus datos (Cliente, Vendedor, Instalador, etc.) en línea, seguida de sus subprocesos en filas compactas con el % de avance en una cajita clara. Hoy la app muestra esos mismos datos en una lista vertical ("Datos": una línea por campo) en el detalle de proyecto, mientras que "Seguimiento" ya tiene algo parecido a una franja (el `card-header` con los campos en línea) pero dentro de una tarjeta con borde, no como una banda de color. Además, el HTML de la tabla de etapas está duplicado palabra por palabra entre `projects/show.html.erb` y `projects/tracker.html.erb`.

## Alcance

1. **Franja de datos con el color del tema** (`bg-primary`, el grafito ya establecido — no el olivo del Excel, para mantener una sola identidad visual) — reemplaza la lista vertical "Datos" en el detalle de proyecto, y reemplaza el `card-header` con borde de "Seguimiento".
2. **Tabla de etapas compartida** — un solo partial usado por ambas vistas, eliminando la duplicación actual.
3. **% Avance con estilo de "cajita"** — el mismo `number_field` editable, pero angosto, centrado y con fondo gris claro, para leerse como el recuadro `100 %` del Excel.
4. **Fechas más angostas** — mismo `date_field`, con un ancho máximo menor para que la tabla se sienta más compacta.
5. **"Seguimiento" deja de usar tarjetas con borde por proyecto** — la franja de color + el nombre arriba ya cumplen el rol de separar visualmente un proyecto del siguiente, sin necesitar un `.card` extra alrededor (más plano, más parecido a una hoja de cálculo continua).

Fuera de alcance: replicar la cuadrícula de fechas/semana del Excel (ya existe el Gantt, que cumple ese rol de forma interactiva), colores de franja distintos por proyecto (todas usan el mismo `bg-primary` — diferenciarlas por color no fue pedido y competiría visualmente con los colores de `StageTemplate`/`Installer` que ya existen en el Gantt).

## 1. Partial `_data_band.html.erb`

```erb
<%# locals: project:, fields: %>
<div class="bg-primary text-white px-3 py-2 rounded d-flex flex-wrap gap-4 mb-4">
  <% fields.each do |field| %>
    <div>
      <small class="text-white-50 d-block"><%= field.label %></small>
      <%= project.custom_fields[field.key] %>
    </div>
  <% end %>
</div>
```

- En `projects/show.html.erb`: se le pasan **todos** los `field_definitions` del tipo (reemplaza la lista "Datos" completa, no solo los `show_in_gantt`).
- En `projects/tracker.html.erb`: se le pasan solo los `show_in_gantt` (igual que hoy).

## 2. Partial `_stage_table.html.erb`

```erb
<%# locals: project: %>
<%= form_with model: project do |f| %>
  <table class="table table-sm table-bordered mb-0 stage-table">
    <thead>
      <tr><th>Etapa</th><th>Inicio</th><th>Fin</th><th>% Avance</th></tr>
    </thead>
    <tbody>
      <%= f.fields_for :project_stages, project.project_stages.includes(:stage_template).order(:id) do |sf| %>
        <tr id="stage-<%= sf.object.id %>">
          <td><%= sf.object.name %></td>
          <td><%= sf.hidden_field :id %><%= sf.date_field :start_date, class: "form-control form-control-sm fecha-input" %></td>
          <td><%= sf.date_field :end_date, class: "form-control form-control-sm fecha-input" %></td>
          <td><%= sf.number_field :progress_percent, min: 0, max: 100, class: "form-control form-control-sm avance-input" %></td>
        </tr>
      <% end %>
    </tbody>
  </table>
  <%= f.submit "Guardar cambios", class: "btn btn-primary btn-sm mt-3" %>
<% end %>
```

Reemplaza el `<table>` inline que hoy existe (casi idéntico) tanto en `show.html.erb` (dentro de la tarjeta "Cronograma", después del Gantt) como en `tracker.html.erb` (dentro de cada bloque de proyecto). El `id="stage-<%= sf.object.id %>"` ya lo usa el Gantt del detalle para el scroll al hacer clic — en `tracker.html.erb` simplemente no se usa (no hay Gantt ahí), pero no estorba.

## 3 y 4. CSS de celdas compactas

`app/assets/stylesheets/application.css` agrega:

```css
.avance-input {
  width: 4.5rem;
  text-align: center;
  background-color: #f1f1f1;
  border-radius: 999px;
}

.fecha-input {
  max-width: 130px;
}
```

## 5. `projects/show.html.erb` — reemplazo de la tarjeta "Datos"

```erb
<%= render "data_band", project: @project, fields: @project.project_type.field_definitions %>
```

(reemplaza el bloque `<div class="card mb-4"><div class="card-header">Datos</div>...</div>` completo). La tarjeta "Cronograma" no cambia de estructura, solo su `<table>` interno pasa a `<%= render "stage_table", project: @project %>`.

## 6. `projects/tracker.html.erb` — bloque por proyecto sin `.card`

```erb
<% @projects.each do |project| %>
  <div class="mb-4">
    <div class="d-flex justify-content-between align-items-center mb-2">
      <%= link_to project.name, project_path(project), class: "fw-bold text-decoration-none fs-5" %>
      <%= status_badge(project.status) %>
    </div>
    <%= render "data_band", project: project, fields: gantt_fields %>
    <%= render "stage_table", project: project %>
  </div>
<% end %>
```

## Testing

- Controlador: `show` — la franja de datos aparece con **todos** los campos del tipo (no solo `show_in_gantt`), con la clase `bg-primary`; la tabla de etapas sigue funcionando igual (mismos tests de arrastre/guardado ya existentes, sin cambios de comportamiento).
- Controlador: `tracker` — la franja de datos aparece con los campos `show_in_gantt`; ya no hay `.card` envolviendo cada bloque de proyecto (se ajusta el test existente que buscaba `.card-header`); la tabla de etapas sigue guardando de forma independiente por proyecto (test ya existente).
- No hay test automatizado para el aspecto visual exacto (colores/anchos, CSS puro) — se verifica manualmente.

## Edge cases

- Un proyecto sin ningún `custom_fields` value para un campo: la franja de datos ya maneja esto igual que la lista vertical lo hacía (`nil` se muestra vacío, no rompe).
- Un tipo de proyecto sin ningún campo marcado `show_in_gantt`: en "Seguimiento", la franja de datos se renderiza vacía (sin `<div>` internos) — no rompe, solo se ve como una banda de color sin contenido. Ya era un caso posible antes de este cambio (la sección de campos ya podía estar vacía).
