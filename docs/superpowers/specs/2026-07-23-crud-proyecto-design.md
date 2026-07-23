# Pulido de los formularios Nuevo/Editar proyecto — design

## Contexto

Los formularios de alta/edición de proyecto (`projects#new`/`#edit`) quedaron sin el pulido visual del resto de la app: sin tarjeta contenedora, sin link para cancelar, y `edit.html.erb` no muestra el nombre del proyecto que se está editando (solo "Editar proyecto" a secas, a diferencia de `new.html.erb` que sí incluye el tipo).

## Alcance

1. **Tarjeta contenedora** en `new.html.erb`/`edit.html.erb` (mismo patrón `.card`/`.card-body` que el resto de la app).
2. **Título con contexto** — `edit.html.erb` pasa a "Editar proyecto — `<nombre>`", igual que ya hace `new.html.erb` con el tipo.
3. **Link "Cancelar"** junto al botón de guardar, en `_form.html.erb` — vuelve a `project_path(project)` si el proyecto ya existe (edición), o a `projects_path` si es nuevo (todavía no hay detalle al que volver).

Fuera de alcance: cambios a `_field_input.html.erb` (los campos dinámicos ya funcionan y usan `form-control`/`form-select` consistentes con el resto).

## Cambios

`app/views/projects/new.html.erb`:

```erb
<h1>Nuevo proyecto — <%= @project_type.name %></h1>
<div class="card">
  <div class="card-body">
    <%= render "form", project: @project, project_type: @project_type %>
  </div>
</div>
```

`app/views/projects/edit.html.erb`:

```erb
<h1>Editar proyecto — <%= @project.name %></h1>
<div class="card">
  <div class="card-body">
    <%= render "form", project: @project, project_type: @project_type %>
  </div>
</div>
```

`app/views/projects/_form.html.erb`, el bloque final:

```erb
  <%= form.submit class: "btn btn-primary" %>
  <%= link_to "Cancelar", project.persisted? ? project_path(project) : projects_path, class: "btn btn-outline-secondary" %>
<% end %>
```

## Testing

- Controlador: `new` — el título incluye el nombre del tipo de proyecto (ya lo hacía, se agrega assert explícito), el formulario está dentro de una tarjeta, hay un link "Cancelar" a `projects_path`.
- Controlador: `edit` — el título incluye el nombre del proyecto, el formulario está dentro de una tarjeta, hay un link "Cancelar" a `project_path(project)`.

## Edge cases

- Ninguno nuevo — el link "Cancelar" usa `project.persisted?`, que ya distingue correctamente los dos casos sin necesitar lógica extra en el controlador.
