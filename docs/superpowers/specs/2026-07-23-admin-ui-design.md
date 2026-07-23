# Pulido de las vistas de Administración, fix de borrado roto — design

## Contexto

Revisando Administración para el pulido de UX encontré un bug real y reproducible: los links "Eliminar" de Campos y Subprocesos en `admin/project_types/show.html.erb` usan `data: { turbo_method: :delete, turbo_confirm: "..." }`, pero esta app **no carga Turbo** (`javascript_importmap_tags` nunca está en el layout — confirmado en una ronda anterior). Sin el JS de Turbo, ese `data-turbo-method` no intercepta nada: el link se sigue como un `GET` plano, que no coincide con ninguna ruta (`resources ..., except: [:index, :show]` no tiene una ruta `GET` para ese path) y devuelve un 404 — reproducido directamente con una request de prueba. Hoy es imposible borrar un Campo o un Subproceso desde la interfaz. El botón "Borrar" de Instaladores sí funciona porque ya usa `button_to` (un formulario real con `_method=delete`), no un link con atributo de Turbo.

## Alcance

1. **Fix del borrado roto** — Campos y Subprocesos pasan de `link_to ... data: { turbo_method: }` a `button_to` (mismo patrón que ya funciona en Instaladores).
2. **Confirmación nativa antes de borrar** — ya que se tocan estos tres botones de borrado (Campos, Subprocesos, Instaladores), se agrega `onclick="return confirm('...')"` a los tres — es HTML/JS nativo del navegador, no depende de Turbo ni de ningún framework, y hoy ninguno de los tres tiene confirmación (`data-confirm`/`data-turbo-confirm` tampoco funcionarían sin Turbo/rails-ujs cargado, así que agregarlos habría sido igual de inútil que lo que ya estaba roto).
3. **Tarjetas para "Campos" y "Subprocesos"** en `admin/project_types/show.html.erb` — mismo patrón que ya se usó para "Datos"/"Cronograma" en el detalle de proyecto (Ronda 3).

Fuera de alcance: agregar un botón de borrado para `ProjectType` en sí (no existe hoy en ninguna vista, no fue pedido — el controlador ya lo soporta si se necesita vía otra vía), rediseño de `admin/installers/index.html.erb` (ya sigue el mismo patrón de lista simple que se deja igual por consistencia con `project_types/index.html.erb`).

## 1 y 2. Fix de borrado + confirmación

`app/views/admin/project_types/show.html.erb`, cada `link_to "Eliminar", ...` pasa de:

```erb
<%= link_to "Eliminar", admin_project_type_field_definition_path(@project_type, field), data: { turbo_method: :delete, turbo_confirm: "¿Eliminar campo?" }, class: "btn btn-outline-danger btn-sm" %>
```

a:

```erb
<%= button_to "Eliminar", admin_project_type_field_definition_path(@project_type, field), method: :delete,
      class: "btn btn-outline-danger btn-sm", form: { style: "display:inline-block", onsubmit: "return confirm('¿Eliminar campo?')" } %>
```

(mismo cambio para el de subprocesos, con el texto "¿Eliminar subproceso?"). El `confirm()` va en `onsubmit` del `<form>` que genera `button_to` (no en el botón), porque interceptar el `submit` del formulario es lo que efectivamente puede cancelar el envío si el usuario dice que no — un `onclick` en el botón por sí solo no detiene el `submit` del formulario que ese mismo clic dispara.

`app/views/admin/installers/index.html.erb` — mismo tratamiento en su `button_to` existente, que hoy no tiene ninguna confirmación:

```erb
<%= button_to "Borrar", admin_installer_path(installer), method: :delete,
      class: "btn btn-outline-danger btn-sm",
      form: { style: "display:inline-block", onsubmit: "return confirm('¿Eliminar instalador?')" } %>
```

## 3. Tarjetas en `admin/project_types/show.html.erb`

```erb
<h1><%= @project_type.name %></h1>
<%= link_to "Editar", edit_admin_project_type_path(@project_type), class: "btn btn-outline-secondary btn-sm mb-3" %>

<div class="card mb-4">
  <div class="card-header">Campos</div>
  <div class="card-body">
    <%= link_to "Nuevo campo", new_admin_project_type_field_definition_path(@project_type), class: "btn btn-primary btn-sm mb-2" %>
    <ul class="list-group list-group-flush">
      <% @project_type.field_definitions.each do |field| %>
        <li class="list-group-item d-flex justify-content-between align-items-center">
          <span><%= field.label %> (<%= field.data_type %>)</span>
          <span>
            <%= link_to "Editar", edit_admin_project_type_field_definition_path(@project_type, field), class: "btn btn-outline-secondary btn-sm" %>
            <%= button_to "Eliminar", admin_project_type_field_definition_path(@project_type, field), method: :delete,
                  class: "btn btn-outline-danger btn-sm", form: { style: "display:inline-block", onsubmit: "return confirm('¿Eliminar campo?')" } %>
          </span>
        </li>
      <% end %>
    </ul>
  </div>
</div>

<div class="card mb-4">
  <div class="card-header">Subprocesos</div>
  <div class="card-body">
    <%= link_to "Nuevo subproceso", new_admin_project_type_stage_template_path(@project_type), class: "btn btn-primary btn-sm mb-2" %>
    <ol class="list-group list-group-numbered list-group-flush">
      <% @project_type.stage_templates.each do |stage| %>
        <li class="list-group-item d-flex justify-content-between align-items-center">
          <span><%= stage.name %></span>
          <span>
            <%= link_to "Editar", edit_admin_project_type_stage_template_path(@project_type, stage), class: "btn btn-outline-secondary btn-sm" %>
            <%= button_to "Eliminar", admin_project_type_stage_template_path(@project_type, stage), method: :delete,
                  class: "btn btn-outline-danger btn-sm", form: { style: "display:inline-block", onsubmit: "return confirm('¿Eliminar subproceso?')" } %>
          </span>
        </li>
      <% end %>
    </ol>
  </div>
</div>
```

## Testing

- Controlador: `Admin::FieldDefinitionsController#destroy` — se agrega un test que hace la request `delete` real (ya existía el controlador/ruta, solo faltaba el punto de entrada en la vista) y confirma que la vista renderiza un `<form>` con `action` apuntando a esa ruta y `method: delete` (vía el input oculto `_method`), no un `<a>` con atributos de Turbo.
- Controlador: `Admin::StageTemplatesController#destroy` — mismo tipo de test.
- Se verifica que los tres `<form>` de borrado (campos, subprocesos, instaladores) incluyen `onsubmit="return confirm(...)"` en el HTML renderizado.
- No hay test automatizado para el comportamiento real del diálogo `confirm()` del navegador (requiere un navegador real, fuera del alcance de Minitest) — se verifica manualmente.

## Edge cases

- Un campo o subproceso ya eliminado por otra pestaña antes de confirmar el borrado aquí: el `destroy` del controlador ya maneja esto igual que siempre lo hizo (no es un caso nuevo introducido por este cambio) — `find` lanzaría `RecordNotFound` como cualquier otro `show`/`edit` a un registro inexistente, comportamiento existente sin cambios.
- Cancelar el diálogo `confirm()`: el `onsubmit` devuelve `false`, el formulario nunca se envía, no hay request al servidor — nada se borra.
