# Actualización de frappe-gantt: encabezado sticky + Día/Semana/Mes — design

## Contexto

Se pidió que el encabezado de fechas del Gantt quede fijo al hacer scroll ("sticky"), y poder cambiar el rango visible entre días, semanas y meses. La versión de frappe-gantt usada hoy (0.6.1, cargada vía CDN) no soporta ninguna de las dos cosas. Investigando la librería (fetched y revisado el bundle minificado de jsdelivr), la versión actual (1.2.2) trae **ambas** de fábrica, pero cambió su API de eventos y algunas opciones — no es un simple cambio de número de versión, hay que adaptar la integración.

Hallazgos concretos de la investigación (verificados leyendo el bundle real, no supuestos):
- **Encabezado sticky**: nativo en 1.2.2 (`'.grid-header{...position:sticky;top:0;left:0...}'` en su CSS). Cero código nuestro necesario.
- **Cambio de vista (Día/Semana/Mes/etc.)**: nativo vía `gantt.change_view_mode("Day"|"Week"|"Month"|...)`. La librería también trae un desplegable propio (`view_mode_select: true`), pero sus opciones muestran los nombres en inglés siempre ("Day", "Week", "Month", placeholder "Mode") — el `language` solo traduce los nombres de mes/día, no las etiquetas del selector. Por eso se arman botones propios en español en vez de usar el selector nativo.
- **Eventos**: en 0.6.1 se pasaban como opciones del constructor (`on_click`, `on_date_change`, `on_progress_change`). En 1.2.2 es un patrón de eventos (`gantt.on("click", fn)`, `gantt.on("date_change", fn)`, `gantt.on("progress_change", fn)`) — se llama después de crear el gráfico, no como opciones.
- **Solo lectura nativa**: 1.2.2 tiene `readonly_dates`/`readonly_progress` como opciones — reemplaza el truco manual que usábamos en el Gantt de solo lectura (`index`), que refrescaba el gráfico para deshacer visualmente cualquier arrastre.
- **Altura/scroll del contenedor**: 1.2.2 tiene `container_height` (número en px, o `"auto"`) — cuando es un número, su propio `.gantt-container` interno (que ya trae `overflow:auto`) se limita a esa altura y scrollea solo, con el header sticky funcionando correctamente adentro. Reemplaza nuestro `style="max-height: 630px; overflow-y: auto;"` manual, que generaba un contenedor de scroll redundante anidado con el propio de la librería.
- **`custom_class`**: sigue agregándose exactamente igual a la clase del grupo de la barra (`bar-wrapper`), así que el coloreado por instalador/etapa (nuestro CSS `.gantt .bar-wrapper.installer-color-X .bar { fill: ... }`) sigue funcionando sin cambios.
- **`language: "es"`**: sigue existiendo como opción, pero ahora delega en el `Intl` nativo del navegador (no hay una tabla de meses embebida en el bundle) — debería seguir funcionando igual o mejor, sin datos de traducción de nuestro lado.
- **Popup nativo**: se puede desactivar con `popup: false` (no lo usamos, navegamos directo al hacer clic).
- **Botón "Today"**: viene activado por defecto (`today_button: true`) y su texto está en inglés — se desactiva explícitamente (`today_button: false`, no fue pedido).
- **`gantt.refresh(tasks)`**: sigue existiendo en 1.2.2 con la misma firma — se mantiene para el caso de error al guardar en el Gantt editable (revertir visualmente si falla el `fetch`).

## Alcance

Actualizar frappe-gantt de 0.6.1 a 1.2.2 en los 2 lugares donde efectivamente se renderiza un Gantt:
1. **`app/views/projects/_project_type_section.html.erb`** — Gantt de solo lectura, uno por sección de tipo de proyecto en `/projects`.
2. **`app/views/projects/show.html.erb`** — Gantt editable (arrastrar fechas/avance) del detalle de un proyecto.

(`projects#tracker` no tiene su propio Gantt — solo usa `_stage_table`, la tabla editable — así que no se toca.)

Cada uno de los dos Gantt gana: encabezado sticky (gratis, sin código), altura/scroll vía `container_height: 630` en vez de CSS manual, y 3 botones propios "Día"/"Semana"/"Mes" que llaman a `gantt.change_view_mode(...)`.

Fuera de alcance: opciones de vista más allá de Día/Semana/Mes (la librería también ofrece Hora/Cuarto de día/Media día/Año — no se pidieron, no se agregan, YAGNI). Persistir la vista elegida entre recargas de página (arranca siempre en "Día", sin guardar preferencia). Cambios a `projects#tracker`.

## Diseño

### `app/views/projects/_project_type_section.html.erb`

Reemplazar el link de CSS:

```erb
<link href="https://cdn.jsdelivr.net/npm/frappe-gantt@0.6.1/dist/frappe-gantt.css" rel="stylesheet">
```

por:

```erb
<link href="https://cdn.jsdelivr.net/npm/frappe-gantt@1.2.2/dist/frappe-gantt.css" rel="stylesheet">
```

Reemplazar el bloque del Gantt:

```erb
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
```

por:

```erb
      <div class="btn-group btn-group-sm mb-2" role="group" id="view-mode-<%= slug %>">
        <button type="button" class="btn btn-outline-secondary view-mode-btn active" data-mode="Day">Día</button>
        <button type="button" class="btn btn-outline-secondary view-mode-btn" data-mode="Week">Semana</button>
        <button type="button" class="btn btn-outline-secondary view-mode-btn" data-mode="Month">Mes</button>
      </div>
      <div id="gantt-<%= slug %>" class="mb-0"></div>

      <script type="application/json" id="gantt-tasks-<%= slug %>"><%== gantt_tasks.to_json %></script>

      <script src="https://cdn.jsdelivr.net/npm/frappe-gantt@1.2.2/dist/frappe-gantt.umd.js"></script>
      <script>
        document.addEventListener("DOMContentLoaded", function () {
          var tasks = JSON.parse(document.getElementById("gantt-tasks-<%= slug %>").textContent);
          if (tasks.length > 0) {
            var gantt = new Gantt("#gantt-<%= slug %>", tasks, {
              language: "es",
              readonly_dates: true,
              readonly_progress: true,
              popup: false,
              today_button: false,
              container_height: 630,
              view_mode_select: false
            });
            gantt.on("click", function (task) { window.location = task.edit_url; });

            document.querySelectorAll("#view-mode-<%= slug %> .view-mode-btn").forEach(function (btn) {
              btn.addEventListener("click", function () {
                gantt.change_view_mode(btn.dataset.mode);
                document.querySelectorAll("#view-mode-<%= slug %> .view-mode-btn").forEach(function (b) { b.classList.remove("active"); });
                btn.classList.add("active");
              });
            });
          }
        });
      </script>
```

### `app/views/projects/show.html.erb`

Reemplazar el link de CSS (mismo cambio de versión que arriba).

Reemplazar el bloque del Gantt editable:

```erb
    <div id="gantt" class="mb-4"></div>

    <script type="application/json" id="gantt-tasks"><%== gantt_tasks.to_json %></script>

    <script src="https://cdn.jsdelivr.net/npm/frappe-gantt@0.6.1/dist/frappe-gantt.min.js"></script>
    <script>
      function toDateInputValue(date) {
        var year = date.getFullYear();
        var month = String(date.getMonth() + 1).padStart(2, "0");
        var day = String(date.getDate()).padStart(2, "0");
        return year + "-" + month + "-" + day;
      }

      document.addEventListener("DOMContentLoaded", function () {
        var tasks = JSON.parse(document.getElementById("gantt-tasks").textContent);
        if (tasks.length === 0) return;

        function saveStage(stageId, attrs) {
          fetch("<%= project_path(@project) %>", {
            method: "PATCH",
            headers: {
              "Content-Type": "application/json",
              "Accept": "application/json",
              "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
            },
            body: JSON.stringify({
              project: { project_stages_attributes: { "0": Object.assign({ id: stageId }, attrs) } }
            })
          })
            .then(function (response) {
              if (!response.ok) throw new Error("save failed");
              return response.json();
            })
            .then(function (stages) {
              var updated = stages.find(function (s) { return String(s.id) === String(stageId); });
              if (!updated) return;
              var row = document.getElementById("stage-" + stageId);
              row.querySelector("input[name*='[start_date]']").value = updated.start_date || "";
              row.querySelector("input[name*='[end_date]']").value = updated.end_date || "";
              row.querySelector("input[name*='[progress_percent]']").value = updated.progress_percent;
            })
            .catch(function () {
              gantt.refresh(tasks);
              alert("No se pudo guardar el cambio. Intenta de nuevo.");
            });
        }

        var gantt = new Gantt("#gantt", tasks, {
          language: "es",
          on_click: function (task) { window.location.hash = "stage-" + task.id; },
          on_date_change: function (task, start, end) {
            saveStage(task.id, { start_date: toDateInputValue(start), end_date: toDateInputValue(end) });
          },
          on_progress_change: function (task, progress) {
            saveStage(task.id, { progress_percent: Math.round(progress) });
          }
        });
      });
    </script>
```

por:

```erb
    <div class="btn-group btn-group-sm mb-2" role="group" id="view-mode-show">
      <button type="button" class="btn btn-outline-secondary view-mode-btn active" data-mode="Day">Día</button>
      <button type="button" class="btn btn-outline-secondary view-mode-btn" data-mode="Week">Semana</button>
      <button type="button" class="btn btn-outline-secondary view-mode-btn" data-mode="Month">Mes</button>
    </div>
    <div id="gantt" class="mb-4"></div>

    <script type="application/json" id="gantt-tasks"><%== gantt_tasks.to_json %></script>

    <script src="https://cdn.jsdelivr.net/npm/frappe-gantt@1.2.2/dist/frappe-gantt.umd.js"></script>
    <script>
      function toDateInputValue(date) {
        var year = date.getFullYear();
        var month = String(date.getMonth() + 1).padStart(2, "0");
        var day = String(date.getDate()).padStart(2, "0");
        return year + "-" + month + "-" + day;
      }

      document.addEventListener("DOMContentLoaded", function () {
        var tasks = JSON.parse(document.getElementById("gantt-tasks").textContent);
        if (tasks.length === 0) return;

        function saveStage(stageId, attrs) {
          fetch("<%= project_path(@project) %>", {
            method: "PATCH",
            headers: {
              "Content-Type": "application/json",
              "Accept": "application/json",
              "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
            },
            body: JSON.stringify({
              project: { project_stages_attributes: { "0": Object.assign({ id: stageId }, attrs) } }
            })
          })
            .then(function (response) {
              if (!response.ok) throw new Error("save failed");
              return response.json();
            })
            .then(function (stages) {
              var updated = stages.find(function (s) { return String(s.id) === String(stageId); });
              if (!updated) return;
              var row = document.getElementById("stage-" + stageId);
              row.querySelector("input[name*='[start_date]']").value = updated.start_date || "";
              row.querySelector("input[name*='[end_date]']").value = updated.end_date || "";
              row.querySelector("input[name*='[progress_percent]']").value = updated.progress_percent;
            })
            .catch(function () {
              gantt.refresh(tasks);
              alert("No se pudo guardar el cambio. Intenta de nuevo.");
            });
        }

        var gantt = new Gantt("#gantt", tasks, {
          language: "es",
          popup: false,
          today_button: false,
          container_height: 630,
          view_mode_select: false
        });
        gantt.on("click", function (task) { window.location.hash = "stage-" + task.id; });
        gantt.on("date_change", function (task, start, end) {
          saveStage(task.id, { start_date: toDateInputValue(start), end_date: toDateInputValue(end) });
        });
        gantt.on("progress_change", function (task, progress) {
          saveStage(task.id, { progress_percent: Math.round(progress) });
        });

        document.querySelectorAll("#view-mode-show .view-mode-btn").forEach(function (btn) {
          btn.addEventListener("click", function () {
            gantt.change_view_mode(btn.dataset.mode);
            document.querySelectorAll("#view-mode-show .view-mode-btn").forEach(function (b) { b.classList.remove("active"); });
            btn.classList.add("active");
          });
        });
      });
    </script>
```

Nota: `_stage_table.html.erb` (la tabla editable de fechas, sin relación con el Gantt en sí) no se toca — su JS de Duración (días) es independiente de esta actualización.

## Testing

- Controlador: ambos Gantt cargan el bundle CDN de la versión 1.2.2 (no 0.6.1).
- Controlador: ambos Gantt muestran los 3 botones "Día"/"Semana"/"Mes".
- Controlador: el Gantt de solo lectura (`_project_type_section.html.erb`) incluye `readonly_dates: true` y `readonly_progress: true` en su configuración.
- Controlador: el div `#gantt-<slug>` ya no tiene el `style="max-height...overflow-y..."` manual (reemplazado por la opción `container_height`).
- Controlador: el coloreado por instalador (CSS `.installer-color-X`) sigue presente igual que antes.
- Manual (no verificable en un test de integración sin navegador real, igual que los scripts anteriores de esta app): el encabezado queda fijo al scrollear verticalmente con más de 15 proyectos; los botones Día/Semana/Mes cambian el rango visible; arrastrar una barra en el Gantt editable sigue guardando el cambio.

## Edge cases

- Los botones Día/Semana/Mes no persisten la elección entre recargas de página — cada carga arranca en "Día" (confirmado, fuera de alcance guardar preferencia).
- Si el fetch de guardado falla en el Gantt editable, `gantt.refresh(tasks)` sigue revirtiendo visualmente el arrastre — comportamiento sin cambios.
- El popup nativo de la librería queda desactivado (`popup: false`) en ambos Gantt — no se usa en ningún lado de esta app.
