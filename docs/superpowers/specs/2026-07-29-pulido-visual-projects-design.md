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

## Edge cases

- Ninguno nuevo — es un pulido puramente visual sobre vistas ya existentes y probadas; el único riesgo real es el del hallazgo ya resuelto arriba (tracker sin tarjetas, respetado).
