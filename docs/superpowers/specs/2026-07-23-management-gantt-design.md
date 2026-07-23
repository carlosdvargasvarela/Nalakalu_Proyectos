# Vista gerencial multi-proyecto, edición visible y color por subproceso — design

## Contexto

La plataforma ya tiene: tipos de proyecto dinámicos, admin CRUD, un Gantt real por proyecto (Frappe Gantt) con etapas editables (fechas, % avance, responsable). Falta una vista de alto nivel para gerencia — todos los proyectos de un tipo en un solo Gantt, filtrable — y dos piezas menores que quedaron sin exponer: el enlace para editar un proyecto existente (el formulario ya existe, `projects#edit`/`#update`, del plan original — nunca se enlazó desde ninguna vista), y color configurable por subproceso.

## Alcance

1. **`Project#start_date`/`#end_date` derivados** — el inicio del proyecto es el `start_date` mínimo entre sus `ProjectStage`; el cierre es el `end_date` máximo. Sin columna nueva.
2. **Enlaces "Editar" visibles** — en `projects/index` y `projects/show`.
3. **`StageTemplate#color`** — campo hex, editable en el admin, con default gris.
4. **Gantt gerencial** (`GET /projects/dashboard`) — una barra por proyecto, filtrable por `project_type` y `status`, coloreada según la etapa actual del proyecto.

Fuera de alcance: notificaciones, exportar a PDF/Excel, drag-to-reschedule en el Gantt (Frappe Gantt lo soporta pero requeriría un endpoint de guardado por drag, no pedido), colores por proyecto individual (se descartó a favor de color por `StageTemplate`, ver brainstorming).

## 1. `Project#start_date` / `#end_date`

```ruby
def start_date
  project_stages.minimum(:start_date)
end

def end_date
  project_stages.maximum(:end_date)
end
```

Ambos pueden devolver `nil` si ninguna etapa tiene fecha (proyecto recién creado). El fallback visual de una semana ya existente en `projects/show.html.erb` (el bloque `ponytail:` que hoy vive inline en la vista) se **centraliza** en el modelo:

```ruby
def gantt_window
  first = start_date || created_at.to_date
  last = end_date || (first + 7.days)
  [first, last]
end
```

`projects/show.html.erb` deja de calcular el fallback por etapa individualmente para el rango del proyecto; cada etapa sigue usando su propio fallback si le falta una fecha (eso no cambia — es por-etapa, no por-proyecto). `gantt_window` es lo que consume la vista gerencial para dibujar la barra completa del proyecto.

## 2. Enlaces "Editar"

- `projects/index.html.erb`: una columna o botón "Editar" por fila, junto al nombre.
- `projects/show.html.erb`: un botón "Editar" junto al título, mismo patrón que `admin/project_types/show.html.erb` ya usa (`link_to "Editar", edit_..._path`).

Sin cambios de controlador — `edit`/`update` ya existen y funcionan (confirmado: `app/controllers/projects_controller.rb` ya los tiene desde el plan original).

## 3. `StageTemplate#color`

- Migración: `add_column :stage_templates, :color, :string, null: false, default: "#6c757d"`.
- Validación: `validates :color, format: { with: /\A#[0-9a-fA-F]{6}\z/ }` (hex de 6 dígitos, con `#`).
- Admin form (`admin/stage_templates/_form.html.erb`): agrega un campo `form.color_field :color` (input nativo `<input type="color">`, sin JS adicional — YAGNI).
- Consumo:
  - **Gantt por proyecto** (`projects/show.html.erb`, ya existente): cada tarea del Gantt agrega `custom_class: "stage-color-#{stage.stage_template_id}"` (o una clase de "sin template" si `stage_template_id` es `nil`, ej. `"stage-color-none"`), y la vista genera un `<style>` inline con una regla CSS por `stage_template_id` presente en las etapas del proyecto: `.bar-wrapper.stage-color-N .bar { fill: #hexcolor; }` (patrón estándar de Frappe Gantt para colorear barras — la librería no acepta un campo de color directo en `0.6.1`, solo `custom_class` + CSS).
  - **Gantt gerencial** (ver sección 4): mismo mecanismo, pero la clase/color aplicado es el de la "etapa actual" del proyecto, no de una etapa individual.

## 4. Gantt gerencial (`GET /projects/dashboard`)

**Ruta:** `get "projects/dashboard", to: "projects#dashboard", as: :dashboard_projects` (antes de `resources :projects` en `routes.rb`, para que `/projects/dashboard` no choque con `/projects/:id`).

**Controlador** (`ProjectsController#dashboard`):
```ruby
def dashboard
  @project_types = ProjectType.all
  @statuses = Project.distinct.pluck(:status).compact
  @projects = Project.includes(:project_type, :project_stages).all
  @projects = @projects.where(project_type_id: params[:project_type_id]) if params[:project_type_id].present?
  @projects = @projects.where(status: params[:status]) if params[:status].present?
end
```

**Filtros:** dos `<select>` en un `form_with url: dashboard_projects_path, method: :get` — uno con `ProjectType.all` (value = id), otro con `@statuses` (value = status string) — con `include_blank: "Todos"` en ambos. Selección actual reflejada vía `selected:` desde `params`.

**Color de la barra de cada proyecto — "etapa actual":**

`ProjectStage` no tiene columna `position` propia (la heredó conceptualmente de `StageTemplate` al copiarse, pero no la persiste — ver `db/schema.rb`). "Más avanzada" se determina por `id` ascendente: las etapas se crean en orden de `position` del `StageTemplate` dentro de `Project#build_stages_from_template`, así que el orden de creación ya refleja el orden de las fases.

```ruby
# en Project
def current_stage
  project_stages.where("progress_percent > 0").order(:id).last || project_stages.order(:id).first
end
```

Si el proyecto no tiene etapas (caso imposible en la práctica — toda creación de `Project` dispara `build_stages_from_template`, pero un `project_type` sin `stage_templates` produciría un proyecto sin etapas), `current_stage` devuelve `nil` y la barra usa el color por defecto (`#6c757d`).

**Datos del Gantt gerencial:** un task por proyecto — `id`, `name` (nombre del proyecto), `start`/`end` (de `project.gantt_window`), `progress` (promedio de `progress_percent` de sus etapas, redondeado — métrica agregada razonable para un vistazo gerencial), `custom_class` (según `current_stage&.stage_template_id`), `edit_url` → `project_path(project)` (clic lleva al detalle del proyecto, no a editar una etapa — distinto del Gantt por-proyecto donde cada barra es una etapa y lleva a editarla).

**Vista** (`app/views/projects/dashboard.html.erb`): filtros arriba, `<div id="management-gantt">` debajo, mismo patrón de `<script type="application/json">` + Frappe Gantt CDN que ya usa `projects/show.html.erb` — sin filas si `@projects` está vacío (mensaje simple "No hay proyectos con estos filtros").

**Enlace de entrada:** el navbar (`app/views/layouts/_navbar.html.erb`, ya existente) agrega un link "Gerencia" junto a "Proyectos"/"Administración".

## Testing

- Modelo: `Project#start_date`/`#end_date`/`gantt_window` — con etapas con fechas, sin fechas, mezcla; `Project#current_stage` — con progreso parcial, sin progreso, sin etapas.
- Modelo: `StageTemplate#color` — válido con hex de 6 dígitos, inválido sin `#` o con longitud incorrecta.
- Controlador: `ProjectsController#dashboard` — sin filtros (todos los proyectos), filtrado por tipo, filtrado por estado, filtrado combinado; enlaces de filtro presentes.
- Controlador: `projects#index`/`#show` — el enlace "Editar" está presente y apunta a la ruta correcta.
- No hay test automatizado para el renderizado visual de colores en el Gantt (JS/CSS, fuera del alcance de Minitest); se verifica manualmente que el `<style>` generado tiene el color correcto por `stage_template_id`.

## Edge cases

- Proyecto sin etapas (`project_type` sin `stage_templates`, caso ya cubierto como edge case del spec original): `current_stage` es `nil`, `gantt_window` cae en el fallback de una semana desde `created_at`, la barra usa el color default.
- Todas las etapas en 0% de avance: `current_stage` cae en la primera etapa (`project_stages.order(:id).first`), coherente con "el proyecto está en su fase inicial".
- `StageTemplate` borrado después de que una `ProjectStage` ya se creó (comportamiento ya cubierto por el spec original — `stage_template_id` se pone `NULL`): la etapa usa la clase `"stage-color-none"` (color default), no rompe el Gantt.
- Filtro por `status` con un valor que luego deja de existir en ningún `Project` (todos los proyectos con ese status se eliminan/cambian): el `<select>` simplemente no ofrece esa opción en la siguiente carga (se recalcula de `Project.distinct.pluck(:status)` en cada request) — no requiere migración de datos.
