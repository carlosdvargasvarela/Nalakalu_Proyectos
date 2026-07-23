# Reordenar Campos y Subprocesos por arrastre — design

## Contexto

`FieldDefinition` y `StageTemplate` ya tienen una columna `position` que determina su orden (ambas asociaciones en `ProjectType` ya usan `-> { order(:position) }`). Hoy la única forma de cambiar el orden es editar el número de posición manualmente en cada uno, uno por uno. Se agrega arrastrar-y-soltar directamente en la lista de Administración → un tipo de proyecto.

## Alcance

1. **Drag and drop nativo de HTML5** (sin librería nueva) en las listas "Campos" y "Subprocesos" de `admin/project_types/show.html.erb`.
2. **Agarradera (⠿) por fila** — solo ese ícono inicia el arrastre, para no interferir con los botones Editar/Eliminar de la misma fila.
3. **Guardado automático al soltar** — vía `fetch` PATCH a un endpoint nuevo por recurso, mismo patrón ya usado para el arrastre del Gantt (sin recargar la página).
4. **Endpoints `reorder`** — uno para `Admin::FieldDefinitionsController`, otro para `Admin::StageTemplatesController`, cada uno recibe el array de ids en el nuevo orden y actualiza `position` de cada uno según su índice.

Fuera de alcance: reordenar desde el celular con gestos táctiles (el Drag and Drop nativo de HTML5 no funciona en touch sin JS adicional — no se pidió soporte táctil, se puede agregar después si hace falta), deshacer un reordenamiento (recargar la página muestra el orden ya guardado; no hay "Ctrl+Z").

## 1-3. Vista

`app/views/admin/project_types/show.html.erb` — cada `<li>` de ambas listas gana `data-id` y una agarradera:

```erb
<ul class="list-group list-group-flush" id="field-definitions-list">
  <% @project_type.field_definitions.each do |field| %>
    <li class="list-group-item d-flex justify-content-between align-items-center" data-id="<%= field.id %>">
      <span>
        <span class="drag-handle me-2" draggable="true" style="cursor: grab;">⠿</span>
        <%= field.label %> (<%= field.data_type_label %>)
      </span>
      <span>
        <%= link_to "Editar", edit_admin_project_type_field_definition_path(@project_type, field), class: "btn btn-outline-secondary btn-sm" %>
        <%= button_to "Eliminar", admin_project_type_field_definition_path(@project_type, field), method: :delete,
              class: "btn btn-outline-danger btn-sm", form: { style: "display:inline-block", onsubmit: "return confirm('¿Eliminar campo?')" } %>
      </span>
    </li>
  <% end %>
</ul>
```

(mismo tratamiento para `<ol id="stage-templates-list">` con `stage_templates`, agarradera igual).

Script (agregado al final del archivo, mismo patrón de `<script>` inline que ya usa el resto de la app — no hay pipeline de JS separado):

```erb
<script>
  function initDragReorder(listId, url) {
    var list = document.getElementById(listId);
    if (!list) return;
    var dragging;

    list.addEventListener("dragstart", function (e) {
      if (!e.target.classList.contains("drag-handle")) return;
      dragging = e.target.closest("li");
      dragging.classList.add("opacity-50");
    });

    list.addEventListener("dragend", function () {
      if (dragging) dragging.classList.remove("opacity-50");
    });

    list.addEventListener("dragover", function (e) {
      e.preventDefault();
      if (!dragging) return;
      var target = e.target.closest("li");
      if (!target || target === dragging) return;
      var rect = target.getBoundingClientRect();
      var after = (e.clientY - rect.top) > rect.height / 2;
      list.insertBefore(dragging, after ? target.nextSibling : target);
    });

    list.addEventListener("drop", function (e) {
      e.preventDefault();
      if (!dragging) return;
      var ids = Array.from(list.querySelectorAll("li[data-id]")).map(function (li) { return li.dataset.id; });
      dragging = null;
      fetch(url, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
        },
        body: JSON.stringify({ ids: ids })
      });
    });
  }

  document.addEventListener("DOMContentLoaded", function () {
    initDragReorder("field-definitions-list", "<%= reorder_admin_project_type_field_definitions_path(@project_type) %>");
    initDragReorder("stage-templates-list", "<%= reorder_admin_project_type_stage_templates_path(@project_type) %>");
  });
</script>
```

(Solo la agarradera tiene `draggable="true"` — no la fila completa —, así que hacer clic en "Editar"/"Eliminar" nunca inicia un arrastre por accidente. El reordenamiento visual ocurre en vivo durante `dragover` (mover el `<li>` en el DOM apenas pasa por encima de otro); al soltar (`drop`) se lee el orden final del DOM y se manda al servidor — mismo truco ya usado en otros lugares de la app para leer el estado final después de una interacción del usuario.)

## 4. Rutas y controladores

`config/routes.rb`:

```ruby
namespace :admin do
  resources :project_types do
    resources :field_definitions, except: [:index, :show] do
      patch :reorder, on: :collection
    end
    resources :stage_templates, except: [:index, :show] do
      patch :reorder, on: :collection
    end
  end
  resources :installers
end
```

`Admin::FieldDefinitionsController` — nueva acción:

```ruby
def reorder
  Array(params[:ids]).each_with_index do |id, index|
    @project_type.field_definitions.where(id: id).update_all(position: index)
  end
  head :ok
end
```

`Admin::StageTemplatesController` — misma acción, sobre `@project_type.stage_templates`.

(`update_all` en vez de `update` porque no hace falta disparar validaciones/callbacks para reordenar — solo se toca `position`, y el `.where(id: id)` scoped al propio `project_type` evita que alguien mande un id de otro tipo de proyecto y reordene registros ajenos.)

## Testing

- Controlador: `Admin::FieldDefinitionsController#reorder` — manda un array de ids en un orden nuevo, confirma que `field_definitions.order(:position)` refleja ese orden después.
- Controlador: `Admin::StageTemplatesController#reorder` — mismo test.
- Controlador: `reorder` con un id que no pertenece a ese `project_type` — no rompe, simplemente no afecta ningún registro (el `.where` scoped lo filtra).
- Controlador: la vista `project_types#show` — cada `<li>` tiene el atributo `data-id` correcto y el ícono de agarradera (`.drag-handle`).
- No hay test automatizado para el gesto de arrastre en sí (interacción de mouse, fuera del alcance de Minitest) — se verifica manualmente.

## Edge cases

- Arrastrar y soltar en la misma posición (sin mover nada): el `fetch` igual se dispara con el mismo orden — no rompe, solo reescribe las mismas posiciones.
- Un id repetido o vacío en el array (no debería pasar desde el DOM real, pero por seguridad): `Array(params[:ids])` nunca lanza si viene `nil`; un id inexistente en `.where(id: id)` simplemente no actualiza nada, no lanza excepción.
