# Duración (días) para completar la fecha Fin de un subproceso — design

## Contexto

Al editar las fechas de un subproceso (en la tabla de `projects#show` y `projects#tracker`), hoy hay que calcular manualmente la fecha Fin sumando los días de duración al Inicio. Se quiere un campo "Duración (días)" que, al completarse, calcule automáticamente Fin = Inicio + duración — pensado para agilizar la carga de datos.

## Alcance

Una columna nueva "Duración (días)" en `_stage_table.html.erb` (partial compartido por `show` y `tracker`), entre Fin y % Avance. Es un campo puramente visual — sin atributo `name`, nunca se envía al servidor ni se guarda en ninguna columna nueva. Un pequeño script vanilla JS escucha el campo y completa Fin cuando cambia.

Fuera de alcance: persistir la duración como dato (no hay columna nueva, ni migración). Recalcular la duración automáticamente al cargar la página a partir de fechas ya existentes. Actualizar la duración si se edita Fin manualmente después. Validación de que Fin no quede antes que Inicio (ya lo maneja, si corresponde, la validación existente del modelo al guardar).

## Diseño

`app/views/projects/_stage_table.html.erb`, agregar la columna:

```erb
<%= form_with model: project do |f| %>
  <table class="table table-sm table-bordered mb-0 stage-table">
    <thead>
      <tr><th>Etapa</th><th>Inicio</th><th>Fin</th><th>Duración (días)</th><th>% Avance</th><th>Estado</th></tr>
    </thead>
    <tbody>
      <%= f.fields_for :project_stages, project.project_stages.includes(:stage_template).order(:id) do |sf| %>
        <tr id="stage-<%= sf.object.id %>">
          <td><%= sf.object.name %></td>
          <td><%= sf.hidden_field :id %><%= sf.date_field :start_date, class: "form-control form-control-sm fecha-input" %></td>
          <td><%= sf.date_field :end_date, class: "form-control form-control-sm fecha-input" %></td>
          <td><input type="number" min="1" class="form-control form-control-sm duracion-input"></td>
          <td><%= sf.number_field :progress_percent, min: 0, max: 100, class: "form-control form-control-sm avance-input" %></td>
          <td>
            <%= progress_status_badge(sf.object.progress_status) %>
            <%= overdue_badge if sf.object.overdue? %>
          </td>
        </tr>
      <% end %>
    </tbody>
  </table>
  <%= f.submit "Guardar cambios", class: "btn btn-primary btn-sm mt-3" %>
<% end %>

<script>
  document.querySelectorAll(".stage-table tbody tr").forEach(function (row) {
    var duracionInput = row.querySelector(".duracion-input");
    var startInput = row.querySelector("input[name*='[start_date]']");
    var endInput = row.querySelector("input[name*='[end_date]']");
    if (!duracionInput || !startInput || !endInput) return;

    duracionInput.addEventListener("input", function () {
      var days = parseInt(duracionInput.value, 10);
      if (!startInput.value || isNaN(days)) return;
      var start = new Date(startInput.value + "T00:00:00");
      start.setDate(start.getDate() + days);
      endInput.value = start.toISOString().slice(0, 10);
    });
  });
</script>
```

El input de Duración **no tiene atributo `name`** — los navegadores solo envían al servidor los campos de un formulario que tienen `name`, así que este campo queda fuera de `params` automáticamente, sin necesidad de excluirlo explícitamente en el controlador.

El cálculo usa `start.setDate(start.getDate() + days)`, que suma días de calendario correctamente incluso cruzando meses/años (JS `Date` normaliza el desborde). El `T00:00:00` al parsear evita que el `Date` se interprete en UTC y se corra un día por zona horaria al mostrarlo.

## Testing

- Vista: `_stage_table.html.erb` renderiza la columna "Duración (días)" con un `<input type="number">` sin atributo `name`.
- Vista: el script de duración está presente en la página (no se puede probar el cálculo de fecha en un test de integración sin un navegador real — se deja como verificación manual, igual que otros scripts de esta app).

## Edge cases

- Duración vacía o no numérica: el listener no hace nada (`isNaN(days)` corta antes de tocar Fin).
- Inicio vacío al escribir Duración: el listener no hace nada (`!startInput.value` corta antes).
- El campo Duración no persiste entre cargas de página (por diseño, confirmado) — si volvés a entrar a la pantalla, arranca vacío de nuevo, sin importar qué fechas ya estén guardadas.
