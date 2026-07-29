# Pulido visual de las pantallas de Proyectos — design

## Contexto

Una vuelta anterior (`2026-07-28-glowup-admin-y-login-design.md`) llevó el tema visual propio de la app (navy `#2c3e50`, bordes redondeados, sombra sutil en `.card`, helper `admin_card`) al login y a todo `/admin/*`, dejando explícitamente afuera "el resto de `projects/*`". Esta vuelta cierra ese pendiente: `/projects` (pestañas + filtros + listado), `projects#new`/`edit`, y ajustes menores en `/projects/seguimiento`.

Un hallazgo importante: `/projects/seguimiento` (tracker) **no tiene tarjetas a propósito** — un commit anterior ("Replace Datos list and per-project cards with an Excel-style graphite data band") las sacó deliberadamente para lograr un look de planilla densa, acorde a que esta app reemplaza un Excel de seguimiento. Un test (`test "tracker renders each project's data as a graphite band without a bordered card"`) protege ese contrato. Esta vuelta lo respeta: el tracker no gana tarjetas nuevas.

## Alcance

1. **Helper genérico**: `admin_card` se renombra a `panel_card` en `ApplicationHelper` — mismo comportamiento, nombre ya no ligado a `/admin` ya que se usa también en `projects/*`. Los ~11 call sites existentes en `/admin/*` se actualizan al nuevo nombre (sin cambio visual).
2. **`projects/new.html.erb` / `edit.html.erb`**: pasan de `<h1>` suelto + `<div class="card"><div class="card-body">` crudo a `panel_card("Nuevo proyecto — Nombre del tipo")` / `panel_card("Editar proyecto — Nombre del proyecto")`, mismo patrón que ya usan los formularios de `/admin`.
3. **`_project_type_section.html.erb`**: la tarjeta de filtros (hoy un `card` con `card-body` sin header) gana un título "Filtros" vía `panel_card`.
4. **Pestañas de tipo de proyecto** (`projects/index.html.erb`): CSS para que la pestaña activa (`.nav-tabs .nav-link.active`) tome el color del tema en vez del gris/azul por defecto de Bootstrap.
5. **Tracker**: sin tarjetas nuevas (ver hallazgo arriba). Único ajuste: el filtro de tracker gana la misma jerarquía visual que el de `/projects` (ya comparten estructura de `form_with ... class: "row g-2"`, no hace falta tocarlo) — en la práctica, este punto no requiere cambios de código, se deja documentado como decisión explícita de **no** tocar el tracker más allá de lo ya heredado.
6. **Referencia de colores del Gantt (pedido explícito del usuario)**: cada Gantt que colorea sus barras por algo (etapa o responsable) gana una leyenda chica debajo, con un círculo de color + el nombre de a quién/qué pertenece — para no tener que adivinar qué representa cada color. Aplica a los dos Gantt que hoy colorean barras:
   - `projects/show.html.erb` (Gantt de un solo proyecto, colorea por `stage_template` de cada etapa): leyenda con una entrada por etapa, siempre visible (no depende de ningún filtro).
   - `projects/_project_type_section.html.erb` (Gantt del listado de `/projects`, colorea por responsable del tipo elegido en el filtro): leyenda con una entrada por responsable, **solo cuando hay un tipo de responsable elegido en el filtro** (si no hay tipo elegido, no hay color que explicar, tal como ya pasa hoy).
   - El tracker no tiene Gantt (usa `_data_band` + `_stage_table`), así que no aplica ahí.

Fuera de alcance (decidido en brainstorming): tarjetas en el tracker (respeta el look "planilla" existente); rehacer login/`/admin/*` de nuevo (ya cubiertos); nueva paleta de colores o tipografía externa; cambios de datos, lógica o tests de comportamiento más allá de los que el rename de helper y el nuevo `panel_card` en `new`/`edit` tocan mecánicamente.

## Diseño

### Rename `admin_card` → `panel_card`

En `app/helpers/application_helper.rb`:

```ruby
def panel_card(title, &block)
  content_tag(:div, class: "card mb-4") do
    content_tag(:div, title, class: "card-header fw-semibold") +
      content_tag(:div, capture(&block), class: "card-body")
  end
end
```

Cada uno de estos 11 archivos reemplaza `admin_card(` por `panel_card(` (única ocurrencia del nombre viejo en cada uno):

- `app/views/admin/field_definitions/_form.html.erb`
- `app/views/admin/users/index.html.erb`
- `app/views/admin/responsible_types/_form.html.erb`
- `app/views/admin/responsibles/_form.html.erb`
- `app/views/admin/users/_form.html.erb`
- `app/views/admin/project_types/_form.html.erb`
- `app/views/admin/responsibles/index.html.erb`
- `app/views/admin/stage_templates/_form.html.erb`
- `app/views/admin/project_types/index.html.erb`
- `app/views/admin/log_entry_types/_form.html.erb`

El HTML generado es idéntico — cero cambio de markup, solo el nombre del método en la vista. Ningún test de comportamiento (`assert_select` sobre `.card`/`.card-header`, textos, etc.) se ve afectado por este rename.

### `projects/new.html.erb`

```erb
<%= panel_card("Nuevo proyecto — #{@project_type.name}") do %>
  <%= render "form", project: @project, project_type: @project_type %>
<% end %>
```

### `projects/edit.html.erb`

Contenido actual:

```erb
<h1>Editar proyecto — <%= @project.name %></h1>
<div class="card">
  <div class="card-body">
    <%= render "form", project: @project, project_type: @project_type %>
  </div>
</div>
```

Pasa a:

```erb
<%= panel_card("Editar proyecto — #{@project.name}") do %>
  <%= render "form", project: @project, project_type: @project_type %>
<% end %>
```

### `_project_type_section.html.erb` — tarjeta de filtros con título

El bloque actual:

```erb
<div class="card mb-4">
  <div class="card-body">
    <%= form_with url: project_type_projects_path(slug), method: :get, local: true, class: "row g-2" do |form| %>
      ...
    <% end %>
  </div>
</div>
```

pasa a usar `panel_card("Filtros")` envolviendo el mismo `form_with` (sin tocar nada dentro del form):

```erb
<%= panel_card("Filtros") do %>
  <%= form_with url: project_type_projects_path(slug), method: :get, local: true, class: "row g-2" do |form| %>
    ...
  <% end %>
<% end %>
```

### Leyenda de colores del Gantt

Un partial chico y reutilizable, `app/views/projects/_gantt_legend.html.erb`, recibe una lista de `[nombre, color]`:

```erb
<%# locals: (entries:) %>
<div class="d-flex flex-wrap gap-3 mb-3">
  <% entries.each do |name, color| %>
    <span class="d-inline-flex align-items-center gap-1">
      <span class="rounded-circle d-inline-block" style="width: 0.75rem; height: 0.75rem; background-color: <%= color %>;"></span>
      <small><%= name %></small>
    </span>
  <% end %>
</div>
```

**`projects/show.html.erb`**: `stage_colors` pasa de `[template_id, color]` a incluir el nombre:

```ruby
stage_colors = stages.map { |stage| [stage.stage_template_id || "none", stage.stage_template&.name || "Sin subproceso", stage.stage_template&.color || "#6c757d"] }.uniq
```

y, justo antes del `<div id="gantt">`, se agrega:

```erb
<%= render "gantt_legend", entries: stage_colors.map { |_, name, color| [name, color] } %>
```

(El `<% stage_colors.each do |template_id, color| %>` que arma el bloque `<style>` con las reglas CSS por `template_id` pasa a `<% stage_colors.each do |template_id, _name, color| %>` — mismo bucle, ahora ignora el nombre en ese punto ya que ahí solo hace falta `template_id`/`color`.)

**`_project_type_section.html.erb`**: `gantt_colors` pasa de `[r.id, r.color]` a `[r.id, r.name, r.color]`, y justo antes del `<div id="gantt-<%= slug %>">` se agrega la leyenda, solo cuando hay un tipo seleccionado y hay colores que mostrar:

```ruby
gantt_colors = if selected_type
  projects_list.map { |project| project.responsible_for(selected_type) }.compact.uniq.map { |r| [r.id, r.name, r.color] }
else
  []
end
```

```erb
<% if selected_type && gantt_colors.any? %>
  <%= render "gantt_legend", entries: gantt_colors.map { |_, name, color| [name, color] } %>
<% end %>
```

(El bucle que arma el `<style>` de `.responsible-color-*` pasa igual de `|responsible_id, color|` a `|responsible_id, _name, color|`.)

### Pestañas activas con el color del tema

En `app/assets/stylesheets/application.css`, agregar junto a las demás reglas:

```css
.nav-tabs .nav-link.active {
  color: var(--bs-primary);
  border-color: rgba(0, 0, 0, 0.06) rgba(0, 0, 0, 0.06) #fff;
  font-weight: 600;
}
```

## Testing

- El rename de helper no requiere tests nuevos (mismo output HTML); los tests existentes que ya verifican `.card`/`.card-header` en las vistas de `/admin/*` siguen pasando sin cambios.
- `projects/new`/`edit`: los tests `"new shows the project type in the title, wraps the form in a card, and links Cancelar to the list"` y `"edit shows the project name in the title, wraps the form in a card, and links Cancelar to the project"` hoy hacen `assert_select "h1", /Instalaciones/` (resp. `/Torre Norte/`) — como el título pasa a vivir en `.card-header` en vez de un `<h1>` suelto, ambos cambian a `assert_select ".card-header", /Instalaciones/` (resp. `/Torre Norte/`). El resto de cada test (`assert_select ".card form"`, el link "Cancelar") no cambia.
- `_project_type_section.html.erb`: se agrega una aserción de que la tarjeta de filtros ahora tiene un `.card-header` con texto "Filtros".
- Tracker: **ningún cambio** — el test `"tracker renders each project's data as a graphite band without a bordered card"` (`assert_select ".card", count: 0`) se mantiene intacto y debe seguir pasando exactamente igual.
- Leyenda del Gantt: en `show.html.erb`, un test crea un proyecto con dos etapas de distinto `stage_template` (colores distintos) y verifica que la leyenda muestra ambos nombres con su color. En `_project_type_section.html.erb`, un test verifica que la leyenda aparece cuando hay `responsible_type_id` en el filtro y hay responsables asignados, y que **no** aparece sin tipo elegido (mismo criterio que ya rige el coloreado).

## Edge cases

- Un `ProjectStage` sin `stage_template` (`stage_template_id` nulo): ya hoy cae en la entrada `"none"`/gris por defecto — la leyenda le pone el nombre "Sin subproceso" a esa entrada, en vez de dejarla sin explicar.
- El listado de `/projects` con un tipo de responsable elegido pero sin ningún proyecto que tenga asignado a alguien de ese tipo: `gantt_colors` queda vacío, la leyenda no se muestra (ya cubierto por el `if ... gantt_colors.any?`), consistente con que tampoco hay barras coloreadas para explicar.
