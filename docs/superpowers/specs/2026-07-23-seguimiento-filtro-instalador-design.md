# Filtro por instalador en Seguimiento — design

## Contexto

"Seguimiento" (`projects#tracker`) hoy solo filtra por Tipo de proyecto. La pantalla de inicio (`projects#index`) ya tiene un filtro por Instalador, resuelto vía `ProjectsController#filter_by_installer` (busca el `FieldDefinition` con `reference_table: "installers"` del propio tipo, sin hardcodear el nombre de la clave). Se agrega el mismo filtro a Seguimiento, reutilizando ese método privado sin cambios.

## Alcance

1. `tracker` acepta `params[:installer_id]` y filtra con `filter_by_installer` (ya existente).
2. La vista agrega un tercer `<select>` "Instalador" junto al de "Tipo", mismo patrón (`include_blank: "Todos"`, `selected: params[:installer_id]`).

Fuera de alcance: cambios a `filter_by_installer` en sí (ya funciona correctamente y está testeado desde la pantalla de inicio).

## Cambios

`ProjectsController#tracker`:

```ruby
def tracker
  @project_types = ProjectType.all
  @installers = Installer.all
  @project_type = ProjectType.find_by(id: params[:project_type_id]) || ProjectType.first
  @projects = if @project_type
    scope = Project.where(project_type: @project_type).where.not(status: "archived")
                   .includes(project_stages: :stage_template).order(:name)
    params[:installer_id].present? ? filter_by_installer(scope, params[:installer_id]) : scope
  else
    Project.none
  end
end
```

`projects/tracker.html.erb`, dentro del `form_with`:

```erb
  <div class="col-auto">
    <%= form.label :installer_id, "Instalador", class: "form-label" %>
    <%= form.select :installer_id, @installers.collect { |i| [i.name, i.id] },
          { include_blank: "Todos", selected: params[:installer_id] }, class: "form-select" %>
  </div>
```

## Testing

- Controlador: `tracker` filtra correctamente por `installer_id` (un proyecto con ese instalador aparece, uno con otro instalador o sin instalador no aparece) — mismo tipo de test ya existente para `index`.
- Controlador: `tracker` sin `installer_id` sigue mostrando todos los proyectos del tipo (comportamiento actual, sin regresión).

## Edge cases

- Ninguno nuevo — `filter_by_installer` ya maneja el caso de "ningún campo de referencia a instaladores" devolviendo `scope.none` en vez de romper (comportamiento ya existente, reutilizado tal cual).
