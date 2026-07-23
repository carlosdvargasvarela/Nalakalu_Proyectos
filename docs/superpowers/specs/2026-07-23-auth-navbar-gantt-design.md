# Auth (Devise), navbar y Gantt real — design

## Contexto

La plataforma de tipos de proyecto dinámicos (ver `2026-07-22-project-types-y-gantt-dinamico-design.md`) ya tiene modelo de datos, CRUD admin y un formulario dinámico de proyectos funcionando, pero:
- No hay autenticación — cualquiera con la URL entra a todo, incluido `/admin`.
- No hay navegación — solo enlaces sueltos dentro de cada vista.
- El "Gantt" es una tabla HTML estática; `ProjectStage` no tiene UI de edición, así que sus fechas y `progress_percent` quedan siempre vacíos/0.

Este spec cubre las cuatro piezas necesarias para que la app se sienta completa: login, navbar, responsable real de cada etapa, y un Gantt visual editable.

## Alcance

1. **Devise + User** — login simple, sin roles, registro abierto, gatea toda la app.
2. **Navbar** — Bootstrap navbar con enlaces y estado de sesión.
3. **`ProjectStage#user_id`** — reemplaza el `assigned_user_id` suelto por una FK real a `User`.
4. **Edición de etapas + Gantt real** — formulario para fechas/avance/responsable por etapa, y visualización con Frappe Gantt (CDN) en `projects#show`.

Fuera de alcance: roles/permisos diferenciados, recuperación de contraseña por email (Devise `:recoverable` requiere mailer configurado — se omite, YAGNI), edición de la vista de Devise (se usan las vistas default del gem), notificaciones.

## 1. Auth

- `User` (Devise): `database_authenticatable, registerable, rememberable, validatable`. Sin campos extra, sin roles.
- `ApplicationController`: `before_action :authenticate_user!`. Devise gestiona sus propias rutas (`/users/sign_in`, `/users/sign_up`, `/users/sign_out`) sin pasar por ese filtro.
- Vistas de Devise: las que genera el gem por defecto (sin `rails g devise:views`), sin estilizar más allá de heredar el layout con Bootstrap ya cargado.
- Tests: request specs mínimos — visitante anónimo redirigido a login en `/` y en `/admin/project_types`; usuario autenticado puede navegar.

## 2. Navbar

- Partial `app/views/layouts/_navbar.html.erb`, incluido en `application.html.erb` sobre el `yield`.
- Contenido: marca/inicio → `root_path`; enlaces "Proyectos" (`projects_path`) y "Administración" (`admin_project_types_path`); a la derecha, si `user_signed_in?`: email + "Cerrar sesión" (`destroy_user_session_path`, method delete); si no: "Iniciar sesión" / "Registrarse". Como todo el árbol ya requiere sesión, el navbar solo se renderiza con sesión iniciada en la práctica, pero el partial contempla ambos estados por robustez.

## 3. `ProjectStage#user_id`

- Migración: agrega `user_id` (FK a `users`, `null: true`, `foreign_key: true`), luego elimina la columna `assigned_user_id` (dos pasos en la misma migración: `add_reference` + `remove_column`).
- `ProjectStage`: `belongs_to :user, optional: true` (reemplaza cualquier referencia a `assigned_user_id`).
- Vistas (`projects/show.html.erb`, formulario de etapa): muestran `stage.user&.email` en vez del id suelto.

## 4. Edición de etapas + Gantt real

**Datos de la etapa editables:** `start_date`, `end_date`, `progress_percent`, `user_id`. `name` no es editable (viene fijo del `StageTemplate` al crearse).

**Rutas:** anidadas bajo `projects` — `resources :projects do resources :project_stages, only: [:edit, :update] end`.

**Controlador `ProjectStagesController`:** `edit`/`update` estándar, `before_action` para cargar `@project` y `@project_stage` (scoped a `@project.project_stages`, evita editar etapas de otro proyecto por id). Redirige a `project_path(@project)` tras guardar.

**Formulario:** `start_date`/`end_date` (`date_field`), `progress_percent` (`number_field`, min 0 max 100), `user_id` (`select` con `User.all.collect { |u| [u.email, u.id] }`, `include_blank: true`).

**Gantt real en `projects#show`:**
- Reemplaza la tabla de subprocesos actual por un `<div id="gantt">` y, arriba o debajo, la tabla existente de columnas `show_in_gantt` se mantiene tal cual (Frappe Gantt solo dibuja barras, no columnas de datos custom — ver spec original línea 80, que ya distingue "columnas del panel izquierdo" de las barras).
- Frappe Gantt se carga vía CDN (`<script src="https://cdn.jsdelivr.net/npm/frappe-gantt@0.6.1/dist/frappe-gantt.min.js">` + su CSS), mismo patrón que Bootstrap — sin tocar importmap.
- Los datos de las etapas se serializan a JSON inline (`<script type="application/json" id="gantt-tasks">`) desde el controlador/vista: `{ id, name, start, end, progress }` por etapa. Etapas sin `start_date`/`end_date` usan la fecha de creación del proyecto como fallback de una semana (`created_at`..`created_at + 7.days`) — Frappe Gantt exige fechas válidas y no soporta barras "sin fecha"; esto es una aproximación visual explícita, no un dato real, así que se marca con un `ponytail:` comment en el código.
- Un `<script>` inline (no un archivo JS aparte — no hay pipeline de assets JS más allá de importmap sin configurar) instancia `new Gantt("#gantt", tasks)` al cargar la página.
- Cada barra enlaza (vía `edit_project_project_stage_path`) al formulario de edición de esa etapa — Frappe Gantt soporta `on_click` para esto.

## Testing

- Modelo: `ProjectStage` — test de `belongs_to :user, optional: true` (válido con y sin `user`).
- Controlador: `ProjectStagesController` — `update` con datos válidos redirige y persiste; `update` con `progress_percent` fuera de 0-100 (si se agrega validación) o inválido re-renderiza. `edit`/`update` de una etapa que no pertenece al proyecto de la URL da 404 (`ActiveRecord::RecordNotFound` vía scoping).
- Controlador: request specs de auth (login requerido en rutas clave).
- No hay test automatizado para el JS de Frappe Gantt (fuera del alcance de Minitest); se verifica manualmente en navegador que el chart renderiza con barras.

## Edge cases

- Proyecto recién creado (todas las etapas sin fechas): Gantt muestra barras de una semana desde `project.created_at` como placeholder visual, no fechas reales — evita un Gantt vacío/roto en el caso más común (proyecto nuevo).
- Usuario elimina su cuenta o hay 0 usuarios: `user_id` es `optional: true`, así que una etapa sin responsable sigue siendo válida.
- `ProjectStage` con `stage_template_id` nulo (template borrado, comportamiento ya cubierto por el spec anterior): la edición de etapa no depende de `stage_template`, sigue funcionando igual.
