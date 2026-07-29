# Visibilidad del catálogo de Responsables — design

## Contexto

El catálogo de personas (`Responsible`, ej. "Juan Pérez", "Ana Gómez") se administra en `/admin/responsibles`, pero esa pantalla no tiene ningún link de navegación — solo es alcanzable si se conoce la URL de memoria. Además, al editar un tipo de proyecto (`/admin/project_types/:id`) se ve la tarjeta "Tipos de responsable" (las categorías: Instalador, Diseñador) pero no hay forma de ver, desde ahí, qué personas existen para asignar a esas categorías.

## Alcance

- **Navbar**: nuevo link "Responsables" (junto a "Usuarios", solo admin) a `admin_responsibles_path`.
- **`admin/project_types/show.html.erb`**: nueva tarjeta "Responsables", de solo consulta (nombre + badge de color por persona) con un botón "Administrar responsables" que lleva a `/admin/responsibles` para el alta/edición/borrado — el catálogo es global (no depende del tipo de proyecto), así que el CRUD completo sigue viviendo en un solo lugar.

Fuera de alcance: cambiar `Responsible`/`ResponsibleType` de modelo o comportamiento; filtrar el catálogo por tipo de proyecto (una persona no está "atada" a un tipo, puede ser asignada con cualquier `ResponsibleType` de cualquier tipo de proyecto vía `ProjectResponsible`).

## Diseño

### Navbar

En `app/views/layouts/_navbar.html.erb`, junto a `link_to "Usuarios", admin_users_path`:

```erb
<%= link_to "Responsables", admin_responsibles_path, class: "nav-link" %>
```

### `admin/project_types/show.html.erb`

Nueva tarjeta, después de la de "Tipos de responsable":

```erb
<div class="card mb-4">
  <div class="card-header">Responsables</div>
  <div class="card-body">
    <%= link_to "Administrar responsables", admin_responsibles_path, class: "btn btn-outline-secondary btn-sm mb-2" %>
    <ul class="list-group list-group-flush">
      <% Responsible.order(:name).each do |responsible| %>
        <li class="list-group-item">
          <span class="badge me-2" style="background-color: <%= responsible.color %>">&nbsp;</span><%= responsible.name %>
        </li>
      <% end %>
    </ul>
  </div>
</div>
```

## Testing

- Navbar: un test verifica que admin ve el link "Responsables" apuntando a `admin_responsibles_path`, y que gerente/visor no lo ven (mismo criterio que "Usuarios").
- `admin/project_types#show`: un test crea un `Responsible` y verifica que su nombre aparece en la nueva tarjeta.

## Edge cases

- Catálogo vacío (ningún `Responsible` creado todavía): la tarjeta se muestra igual, con la lista vacía y el botón "Administrar responsables" para crear el primero.
