# Gantt editable por arrastre en el detalle de proyecto, fix de colores — design

## Contexto

Dos problemas reportados sobre el Gantt tras las rondas anteriores:

1. **Los colores de `StageTemplate#color` no se respetan al interactuar.** Verificado leyendo `frappe-gantt.css` (misma versión ya usada por la app): la librería trae `.gantt .bar-wrapper:hover .bar { fill: #a9b5c1 }` y `.gantt .bar-wrapper.active .bar { fill: #a9b5c1 }`, ambas con **4** clases de especificidad. Nuestra regla actual, `.bar-wrapper.stage-color-N .bar { fill: color }`, tiene solo **3**. Resultado: el color se pinta bien al cargar la página, pero en cuanto se pasa el mouse o se hace clic sobre una barra (lo que agrega la clase `.active` vía `this.group.classList.add("active")`, confirmado leyendo el JS), la barra vuelve al azul-gris por defecto de la librería — no es un problema de datos ni de caché, ya verificado (`StageTemplate#color` se lee fresco en cada request).
2. **El Gantt del detalle de proyecto no persiste el arrastre.** Desde la Ronda 1 se decidió deliberadamente que ningún Gantt fuera editable por arrastre (`on_date_change`/`on_progress_change` llaman `gantt.refresh(tasks)` para revertir cualquier cambio visual). El usuario ahora pide que, específicamente en el detalle de proyecto (no en la pantalla de inicio, que agrupa por proyecto completo y no tiene una sola etapa a la que mapear un arrastre), arrastrar sí guarde el cambio, y que la tabla de etapas de abajo se actualice sola sin recargar.

## Alcance

1. **Fix de especificidad CSS** — en ambas vistas que pintan el Gantt (`projects/index.html.erb` y `projects/show.html.erb`), la regla de color cubre explícitamente los estados base, `:hover` y `.active`.
2. **Gantt editable por arrastre en `projects#show`** — arrastrar una barra (fecha) o su indicador de avance dispara un guardado por `fetch` a la misma ruta que ya usa el formulario de la tabla (`PATCH /projects/:id`, reutilizando `project_stages_attributes` — sin ruta ni controlador nuevo), y la fila correspondiente de la tabla se actualiza con los valores confirmados por el servidor.
3. **`projects#update` responde JSON además de HTML** — sin cambiar el flujo HTML existente (edición vía formulario, la tabla "Guardar cambios" que sigue siendo un POST normal de página completa).

Fuera de alcance: hacer editable por arrastre el Gantt de la pantalla de inicio (agrupa por proyecto, no por etapa — no hay un mapeo 1:1 claro), reordenar etapas por drag (`frappe-gantt` no lo soporta en esta versión y no se pidió), deshacer/rehacer cambios de arrastre.

## 1. Fix de especificidad CSS

En ambas vistas, la regla:

```css
.bar-wrapper.stage-color-<%= template_id %> .bar { fill: <%= color %>; }
```

pasa a:

```css
.gantt .bar-wrapper.stage-color-<%= template_id %> .bar,
.gantt .bar-wrapper.stage-color-<%= template_id %>:hover .bar,
.gantt .bar-wrapper.stage-color-<%= template_id %>.active .bar {
  fill: <%= color %>;
}
```

(Cada selector iguala o supera la especificidad de la regla equivalente de `frappe-gantt.css` que compite por el mismo elemento — 4 clases contra 4 — y como es un `<style>` en el body, cargado después del `<link>` de la librería en el `<head>`, gana también por orden en caso de empate exacto. No se usa `!important`: alcanza con igualar especificidad y ganar por orden de carga, y `!important` sería más difícil de revertir/depurar después.)

## 2. `projects#update` responde JSON

`app/controllers/projects_controller.rb`:

```ruby
def update
  @project_type = @project.project_type
  if @project.update(project_params)
    respond_to do |format|
      format.html { redirect_to project_path(@project) }
      format.json { render json: stage_payload }
    end
  else
    respond_to do |format|
      format.html { render :edit, status: :unprocessable_entity }
      format.json { render json: { errors: @project.errors.full_messages }, status: :unprocessable_entity }
    end
  end
end

private

def stage_payload
  @project.project_stages.map do |stage|
    { id: stage.id, start_date: stage.start_date, end_date: stage.end_date, progress_percent: stage.progress_percent }
  end
end
```

(El formulario "Guardar cambios" de la tabla sigue siendo un `form_with` normal sin `data: { turbo: false }` ni JS — la app no tiene Turbo Drive cargado en el layout, así que ese submit sigue siendo una recarga completa de página, formato HTML, sin cambios de comportamiento. El único consumidor de `format.json` es el `fetch` nuevo del punto 3.)

## 3. Arrastrar en el Gantt del detalle de proyecto guarda y sincroniza la tabla

En `projects/show.html.erb`, el bloque `<script>` del Gantt cambia de:

```js
var gantt = new Gantt("#gantt", tasks, {
  language: "es",
  on_click: function (task) { window.location.hash = "stage-" + task.id; },
  on_date_change: function () { gantt.refresh(tasks); },
  on_progress_change: function () { gantt.refresh(tasks); }
});
```

a (agrega una función `saveStage` compartida por ambos callbacks):

```js
function toDateInputValue(date) {
  var year = date.getFullYear();
  var month = String(date.getMonth() + 1).padStart(2, "0");
  var day = String(date.getDate()).padStart(2, "0");
  return year + "-" + month + "-" + day;
}

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
```

(`toDateInputValue` usa los componentes de fecha **locales** del objeto `Date` — no `toISOString()`, que convierte a UTC y podría correr la fecha un día según la zona horaria del navegador. Confirmado leyendo `frappe-gantt`: `on_date_change`/`on_progress_change` reciben objetos `Date` nativos de JS, nunca strings, así que `toDateInputValue` siempre recibe un `Date` real.)

`saveStage` reutiliza `project_stages_attributes` con índice `"0"` porque cada llamada actualiza una sola etapa a la vez (igual que hace el formulario "Guardar cambios" cuando se edita una fila) — `accepts_nested_attributes_for :project_stages, update_only: true` (ya existente) no requiere que se envíen todas las etapas juntas.

## Testing

- Controlador: `PATCH /projects/:id` con `Accept: application/json` y `project_stages_attributes` válido — responde `200` con JSON `[{ id:, start_date:, end_date:, progress_percent: }, ...]` reflejando el cambio guardado.
- Controlador: mismo request con datos inválidos (ej. `progress_percent: 150`) — responde `422` con `{ errors: [...] }` en JSON, sin romper (`unprocessable_entity`, no una excepción).
- Controlador: el flujo HTML existente (`PATCH` sin `Accept: application/json`, o la request normal del formulario de la tabla) sigue redirigiendo igual que antes — sin regresión.
- No hay test automatizado para el arrastre en sí (interacción de mouse en SVG, fuera del alcance de Minitest) ni para la especificidad CSS resultante (requeriría un motor de renderizado real) — ambos se verifican manualmente. Sí se puede verificar por test que el `<style>` generado incluye las variantes `:hover`/`.active` (verificación de texto, no de renderizado real).

## Edge cases

- Arrastrar una barra a una fecha que deja `end_date` antes que `start_date`: no hay validación de orden hoy en `ProjectStage` (fuera de alcance agregarla — no fue pedida, y el problema ya existía en el formulario manual antes de este cambio); el guardado igual sucede, la barra visualmente puede verse "invertida" (frappe-gantt ya maneja este caso con su propia clase `.bar-invalid`, sin romper nada).
- Fallo de red durante el guardado (`fetch` rechaza o responde `!ok`): la barra rebota a la posición original vía `gantt.refresh(tasks)` (mismo mecanismo que ya existía para el modo solo-lectura) y se muestra una alerta — el usuario nunca queda con un estado visual que no corresponde a lo guardado.
- Arrastrar la misma barra varias veces seguidas rápido: cada arrastre dispara su propio `fetch` independiente; como cada uno manda el estado completo de esa etapa (no un delta), el último en completarse "gana" — no hay condición de carrera que corrompa datos, aunque en teoría respuestas fuera de orden podrían pisar una actualización más reciente con una más vieja (caso raro, de red, no manejado — aceptado como límite conocido, no se agrega control de versión/timestamp para esto por YAGNI).
