# Arreglo de alineación de botones + íconos — design

## Contexto

En la tabla Listado (y también en la cabecera de `projects#show`), los botones "Editar"/"Archivar" de cada fila aparecen apilados verticalmente con un hueco feo entre ellos, en vez de quedar uno al lado del otro. La causa raíz: `_archive_button.html.erb` usa `form_with(..., style: "display:inline-block")`, pero `form_with` no reconoce la opción `style:` a ese nivel — la ignora silenciosamente, así que el `<form>` generado queda como bloque normal (no en línea), y el botón "Archivar" cae a una línea nueva debajo de "Editar". Además se quiere agregar íconos a ambos botones para un look más profesional.

## Alcance

1. **Arreglar el bug de alineación** — `_archive_button.html.erb` pasa la clase correctamente vía `html: { class: "d-inline" }` en vez del `style:` roto.
2. **Envolver Editar + Archivar en un contenedor flex** con espaciado (`d-flex gap-2`) en la tabla Listado, igual que ya existe en `projects#show` (que resulta beneficiada por el fix del punto 1, ya tenía el wrapper correcto pero el botón interno igual se rompía).
3. **Agregar Bootstrap Icons** vía CDN (solo CSS, mismo proveedor que Bootstrap 5.3.3 ya cargado) — ícono de lápiz (`bi-pencil`) en Editar, ícono de archivo (`bi-archive`) en Archivar, en ambos lugares donde aparecen estos botones.

Fuera de alcance: cualquier otro botón de la aplicación (este cambio es específico de Editar/Archivar). No se agrega ninguna dependencia de JavaScript.

## Diseño

### Bootstrap Icons (CDN)

`app/views/layouts/application.html.erb`, agregar el link de Bootstrap Icons junto al de Bootstrap:

```erb
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.3/font/bootstrap-icons.min.css" rel="stylesheet">
```

### Fix del formulario de Archivar

`app/views/projects/_archive_button.html.erb`, reemplazar:

```erb
<%= form_with(model: project, local: true, method: :patch, style: "display:inline-block") do |f| %>
  <%= f.hidden_field :status, value: "archived" %>
  <%= f.submit "Archivar", class: "btn btn-outline-danger btn-sm" %>
<% end %>
```

con:

```erb
<%= form_with(model: project, local: true, method: :patch, html: { class: "d-inline" }) do |f| %>
  <%= f.hidden_field :status, value: "archived" %>
  <%= f.button type: "submit", class: "btn btn-outline-danger btn-sm" do %>
    <i class="bi bi-archive"></i> Archivar
  <% end %>
<% end %>
```

(Se cambia de `f.submit` a `f.button` porque `f.submit` solo acepta texto plano como label — no puede incluir un `<i>` de ícono adentro. `f.button` con bloque sí permite HTML interno.)

### Tabla Listado — envolver los botones en flex

`app/views/projects/_project_type_section.html.erb`, reemplazar:

```erb
              <td>
                <%= link_to "Editar", edit_project_path(project), class: "btn btn-outline-secondary btn-sm" %>
                <%= render "archive_button", project: project %>
              </td>
```

con:

```erb
              <td>
                <div class="d-flex gap-2">
                  <%= link_to edit_project_path(project), class: "btn btn-outline-secondary btn-sm" do %>
                    <i class="bi bi-pencil"></i> Editar
                  <% end %>
                  <%= render "archive_button", project: project %>
                </div>
              </td>
```

### `projects#show` — agregar el ícono al link de Editar existente

`app/views/projects/show.html.erb`, reemplazar:

```erb
    <%= link_to "Editar", edit_project_path(@project), class: "btn btn-outline-secondary btn-sm" %>
```

con:

```erb
    <%= link_to edit_project_path(@project), class: "btn btn-outline-secondary btn-sm" do %>
      <i class="bi bi-pencil"></i> Editar
    <% end %>
```

(El wrapper `d-flex gap-2` ya existe en este archivo — no hace falta agregarlo, solo se beneficia del fix del formulario de Archivar.)

## Testing

- Controlador: la tabla Listado renderiza el botón "Editar" con el ícono `bi-pencil` y el botón "Archivar" con `bi-archive`, ambos dentro de un `.d-flex`.
- Controlador: `projects#show` renderiza el botón "Editar" con el ícono `bi-pencil`.
- Controlador: el formulario de "Archivar" sigue funcionando (archivar un proyecto sigue poniendo `status: "archived"`) — el cambio de `style:` a `html: { class: }` y de `f.submit` a `f.button` no debe romper el envío del formulario.
- Vista: el layout incluye el link de Bootstrap Icons.

## Edge cases

- El botón "Archivar" pasa de `<input type="submit">` a `<button type="submit">` (necesario para poder anidar el ícono) — el texto visible sigue siendo "Archivar", pero los 2 tests existentes que buscan `assert_select "input[value=?]", "Archivar"` (`test/controllers/projects_controller_test.rb:86` y `:395`) necesitan actualizarse a `assert_select "button", text: /Archivar/` (ya ocurrió un cambio idéntico en una ronda anterior con otros botones `button_to`).
