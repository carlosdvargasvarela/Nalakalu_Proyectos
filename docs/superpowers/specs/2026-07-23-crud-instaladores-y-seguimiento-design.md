# CRUD de instaladores, archivar proyecto y edición inline de etapas — design

## Contexto

La app ya modela el Excel de seguimiento de instalaciones: `Project` (fila del pedido, con `custom_fields` dinámicos) + `ProjectStage` (filas de tarea: Diseño-Aprobación, RI, Producción, Entrega, Instalación), con Gantt por proyecto y Gantt gerencial multi-proyecto ya construidos. Al revisar con el usuario qué le impide reemplazar el Excel hoy, aparecieron tres huecos puntuales, sin relación estructural entre sí:

1. `Installer` (el modelo detrás del campo "Instalador") no tiene controlador ni vistas — no hay forma de dar de alta un instalador nuevo desde la app.
2. No existe manera de sacar un proyecto de las vistas operativas (no hay `destroy` ni archivado).
3. Actualizar el avance de una etapa requiere navegar a una página de edición separada por cada etapa (`project_stages#edit`), cuando el caso de uso real es "actualizar 1-5 etapas de un proyecto de una sentada".

## Alcance

1. **CRUD de `Installer`** en `admin/installers` (index/new/create/edit/update/destroy).
2. **Archivar proyecto** — botón que cambia `status` a `"archived"` reusando `ProjectsController#update`; `projects#index` deja de listar archivados por defecto.
3. **Tabla editable de etapas en `projects#show`** — reemplaza la página de edición por-etapa; se elimina `ProjectStagesController` y su ruta anidada.

Fuera de alcance: borrado físico de proyectos, historial/auditoría de cambios de estado, permisos por rol (cualquier usuario autenticado puede archivar/editar, igual que hoy), edición de instaladores en batch, deshacer un archivado desde la UI (se puede revertir editando el proyecto directamente, no se pide una vista dedicada de "reactivar").

## 1. CRUD de `Installer`

- Ruta: `namespace :admin do resources :installers end` (junto a `project_types`, fuera del bloque anidado de `project_types` porque `Installer` no pertenece a un `ProjectType`).
- `Admin::InstallersController`: mismas 5 acciones que `Admin::StageTemplatesController`/`Admin::FieldDefinitionsController` (index, new, create, edit, update, destroy), sin nesting bajo project_type.
  - `destroy`: si el instalador está referenciado por algún `Project.custom_fields` (campo `reference` a `installers`), el borrado no rompe nada porque no hay FK de base de datos entre `custom_fields` (jsonb) e `installers` — se permite igual, coherente con cómo ya funciona la validación `valid_reference?` en `Project` (revalida en cada guardado, no al borrar el instalador referenciado). No se agrega protección adicional: fuera del alcance pedido.
- Vistas en `app/views/admin/installers/`: `index.html.erb` (tabla nombre + editar/borrar), `new.html.erb`, `edit.html.erb`, `_form.html.erb` (un solo campo `name`) — mismo estilo Bootstrap que `admin/stage_templates`.
- Nav: no existe layout admin compartido (confirmado — cada vista admin usa el layout general de la app). Se agrega el link "Instaladores" → `admin_installers_path` en `admin/project_types/index.html.erb`, que es la puerta de entrada actual a Administración.

## 2. Archivar proyecto

- Sin controlador ni ruta nueva. En `projects/index.html.erb`, por fila:
  ```erb
  <%= button_to "Archivar", project_path(project), params: { project: { status: "archived" } }, method: :patch, class: "btn btn-outline-danger btn-sm" %>
  ```
- `ProjectsController#index`:
  ```ruby
  @projects = Project.includes(:project_type).where.not(status: "archived")
  ```
- `ProjectsController#dashboard` no cambia — sigue mostrando todos los estados y permite filtrar explícitamente por `status` (incluyendo `"archived"`) como ya hace hoy.
- No se requiere cambio en `project_params` — `status` ya está permitido.

## 3. Tabla editable de etapas en `projects#show`

- `Project` agrega:
  ```ruby
  accepts_nested_attributes_for :project_stages, update_only: true
  ```
  (`update_only: true` porque las etapas ya existen — se crean únicamente vía `build_stages_from_template`, nunca desde este formulario.)
- `ProjectsController#project_params` agrega `project_stages_attributes: [:id, :start_date, :end_date, :progress_percent]`.
  - `user_id` (responsable) se deja fuera del alcance de este formulario simplificado — no se pidió, y no hay UI hoy para elegir usuario; se puede agregar después si se pide.
- `projects/show.html.erb`: debajo del Gantt existente, un único `form_with model: @project do |f|` con `f.fields_for :project_stages do |sf|` — una fila de tabla por etapa (nombre en texto plano, `sf.date_field :start_date`, `sf.date_field :end_date`, `sf.number_field :progress_percent`), un solo submit "Guardar cambios".
- El Gantt (`on_click`) deja de apuntar a `edit_project_project_stage_path` (se elimina esa ruta). En su lugar, `on_click` hace scroll a la fila de la tabla correspondiente vía ancla (`#stage-<id>`) — sin JS adicional más allá de `window.location.hash`.
- **Se eliminan** (redundantes frente a la tabla inline): `app/controllers/project_stages_controller.rb`, `app/views/project_stages/edit.html.erb`, la ruta `resources :project_stages, only: [:edit, :update]` anidada en `resources :projects`, y el test correspondiente si existe.

## Testing

- Modelo: `Project#project_stages_attributes=` actualiza fechas/progreso de etapas existentes sin crear ni destruir etapas.
- Controlador: `Admin::InstallersController` — CRUD completo (create válido/inválido, update, destroy, index lista instaladores).
- Controlador: `ProjectsController#index` — excluye proyectos con `status: "archived"`; `#update` con `status: "archived"` archiva correctamente.
- Controlador: `ProjectsController#update` — acepta `project_stages_attributes` y actualiza las etapas anidadas.
- Se retiran los tests de `ProjectStagesController` si existían (funcionalidad eliminada).

## Edge cases

- Un `Project` sin ninguna `ProjectStage` (caso ya cubierto en specs previos como "imposible en la práctica"): la tabla inline no renderiza filas, `fields_for` simplemente no itera — no rompe el formulario.
- Archivar un proyecto no borra sus etapas ni su historial — sigue accesible por URL directa (`projects/:id`) y visible en Gerencia si se filtra por `status: "archived"`.
- Borrar un `Installer` referenciado por proyectos existentes: el proyecto sigue mostrando el `id` guardado en `custom_fields`; si se reintenta guardar ese proyecto, `valid_reference?` lo marcaría inválido (comportamiento ya existente, sin cambios).
