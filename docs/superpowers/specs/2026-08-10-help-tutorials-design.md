# Menú de ayuda: tutoriales en Markdown por vista

## Contexto

La app no tiene ningún sistema de ayuda hoy. Hay 15 controladores; de esos,
`log_entries`, `project_associations` y `project_responsibles`
(app/controllers/log_entries_controller.rb y hermanos) no tienen vistas
propias — solo `create`/`destroy` que redirigen a `projects#show` — así que
no necesitan tutorial propio, su contenido va dentro del de `projects`.

No hay ninguna gem de markdown instalada, ni ningún modal en la app
todavía (`grep -rl "modal" app/views app/javascript` no devuelve nada) —
este es el primer modal que se agrega. Bootstrap 5.3.3 y Bootstrap Icons
1.11.3 ya están cargados vía CDN en el layout
(app/views/layouts/application.html.erb:20-21), así que el modal y los
íconos usan lo que ya está, sin agregar JS nuevo más allá de un controller
de Stimulus (el patrón ya existente, ver
app/javascript/controllers/theme_controller.js).

Toda la app está detrás de login
(`before_action :authenticate_user!, unless: :devise_controller?` en
app/controllers/application_controller.rb:5), así que la ayuda hereda esa
protección sin trabajo extra.

## Cambio

### 1. Contenido: un `.md` por controlador

11 archivos en `docs/help/`, con la misma ruta que `controller_path` del
controlador correspondiente:

```
docs/help/projects.md
docs/help/imports.md
docs/help/admin/project_types.md
docs/help/admin/field_definitions.md
docs/help/admin/stage_templates.md
docs/help/admin/duration_profiles.md
docs/help/admin/log_entry_types.md
docs/help/admin/responsible_types.md
docs/help/admin/responsibles.md
docs/help/admin/project_type_associations.md
docs/help/admin/users.md
```

Cada uno es un borrador inicial en español (el usuario los va a pulir
después): qué es la pantalla, para qué sirve cada acción principal, y
cualquier detalle no obvio (ej. que "duración automática" en tipos de
proyecto reemplaza las fechas manuales de etapa, o que los tipos de
asociación controlan qué combinaciones de tipos de proyecto pueden
vincularse entre sí). El de `projects.md` también cubre agregar
notas de bitácora y vincular/asociar proyectos, ya que esas acciones viven
en `projects#show` sin controlador de vista propio.

### 2. Gem de markdown

Agregar `gem "redcarpet"` al Gemfile — renderer maduro, sin dependencias
nativas complicadas, ya usado ampliamente en el ecosistema Rails.

### 3. Ruta y controlador

Ruta con segmento wildcard (el topic incluye barras, ej.
`admin/project_types`):

```ruby
get "help/*topic", to: "help#show", as: :help_topic
```

`app/controllers/help_controller.rb`:

```ruby
class HelpController < ApplicationController
  def show
    base = Rails.root.join("docs", "help")
    path = base.join("#{params[:topic]}.md").expand_path

    unless path.to_s.start_with?("#{base}/") && path.exist?
      head :not_found and return
    end

    html = Rails.cache.fetch("help/#{params[:topic]}/#{path.mtime.to_i}") do
      Redcarpet::Markdown.new(
        Redcarpet::Render::HTML.new,
        autolink: true, tables: true, fenced_code_blocks: true
      ).render(path.read)
    end

    render html: html.html_safe, layout: false
  end
end
```

El chequeo `path.to_s.start_with?("#{base}/")` después de `expand_path`
es obligatorio: `params[:topic]` viene del usuario y sin ese guard alguien
podría pedir `/help/../../../../etc/passwd` y leer archivos fuera de
`docs/help/`. La cache usa el `mtime` del archivo en la key, así que
editar un `.md` invalida la cache sola, sin necesidad de reiniciar el
server ni limpiar la cache a mano.

`render html: ..., layout: false` devuelve el fragmento HTML puro (sin
`<html>`/`<head>`) para insertarlo directo en el modal.

### 4. Botón contextual automático (sin tocar las 11 vistas)

En vez de agregar el botón a cada una de las 11 vistas a mano, se resuelve
automáticamente en el layout a partir de `controller_path` — así una
vista nueva con su `docs/help/<controller_path>.md` correspondiente
obtiene el botón gratis, sin cambiar código:

`app/helpers/application_helper.rb`, nuevo método:

```ruby
def help_topic_path_if_exists
  Rails.root.join("docs", "help", "#{controller_path}.md").exist? ? controller_path : nil
end
```

`app/views/layouts/application.html.erb`, dentro del `<div class="container py-4">`,
antes del `<%= yield %>` actual:

```erb
<% if (topic = help_topic_path_if_exists) %>
  <div class="text-end mb-2">
    <button type="button" class="btn btn-sm btn-outline-secondary" data-controller="help" data-action="click->help#open" data-help-topic-value="<%= topic %>">
      <i class="bi bi-question-circle"></i> Ayuda
    </button>
  </div>
<% end %>
```

### 5. Menú central en la navbar

`app/views/layouts/_navbar.html.erb`: un ícono "?" fijo (igual estilo que
el botón de tema claro/oscuro ya existente) que abre un modal con la
lista de los 11 tutoriales, agrupados en dos secciones ("Proyectos" e
"Importar" / "Administración"). La lista sale de una constante simple en
el helper:

```ruby
HELP_MENU = [
  { section: "Proyectos", items: [["Proyectos", "projects"], ["Importar", "imports"]] },
  { section: "Administración", items: [
    ["Tipos de proyecto", "admin/project_types"],
    ["Campos", "admin/field_definitions"],
    ["Subprocesos", "admin/stage_templates"],
    ["Perfiles de duración", "admin/duration_profiles"],
    ["Tipos de bitácora", "admin/log_entry_types"],
    ["Tipos de responsable", "admin/responsible_types"],
    ["Responsables", "admin/responsibles"],
    ["Tipos de asociación", "admin/project_type_associations"],
    ["Usuarios", "admin/users"],
  ] },
].freeze
```

Cada ítem de esa lista es un botón con el mismo `data-controller="help"`
que el botón contextual — abre el mismo modal de contenido.

### 6. El modal y el Stimulus controller

Un solo modal de contenido, renderizado una vez en el layout
(`app/views/layouts/application.html.erb`, antes de cerrar `</body>`):

```erb
<div class="modal fade" id="help-modal" tabindex="-1">
  <div class="modal-dialog modal-lg modal-dialog-scrollable">
    <div class="modal-content">
      <div class="modal-header">
        <h5 class="modal-title">Ayuda</h5>
        <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
      </div>
      <div class="modal-body" data-help-target="body">
        <div class="text-center text-muted py-4">Cargando…</div>
      </div>
    </div>
  </div>
</div>
```

Más el modal de menú (misma estructura, `id="help-menu-modal"`, cuerpo con
la lista de `HELP_MENU` renderizada en el layout/navbar, cada link con
`data-controller="help" data-action="click->help#open"` y
`data-bs-dismiss="modal"` para cerrar el menú al elegir un tema).

`app/javascript/controllers/help_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

// Fetches a rendered markdown help topic and shows it in the shared #help-modal.
export default class extends Controller {
  static values = { topic: String }

  async open(event) {
    event.preventDefault()
    const modalEl = document.getElementById("help-modal")
    const body = modalEl.querySelector('[data-help-target="body"]')
    body.innerHTML = '<div class="text-center text-muted py-4">Cargando…</div>'
    bootstrap.Modal.getOrCreateInstance(modalEl).show()

    const response = await fetch(`/help/${this.topicValue}`)
    body.innerHTML = response.ok
      ? await response.text()
      : '<p class="text-danger">No se encontró este tutorial.</p>'
  }
}
```

### 7. Estilos mínimos

`app/assets/stylesheets/application.css`, unas pocas reglas para que el
markdown renderizado (títulos, listas, código inline) se vea prolijo
dentro del `.modal-body`, reusando las variables de Bootstrap ya en uso
en el resto del archivo (`var(--bs-primary)`, `var(--bs-border-color)`,
etc.) — nada de una librería de estilos nueva.

## Fuera de alcance

- No se agrega un editor de tutoriales en la app — los `.md` se editan a
  mano en el repo.
- No hay tutoriales por acción (`new` vs `edit` vs `index` del mismo
  controlador comparten el mismo `.md`), según lo ya decidido.
- No se traduce ni previsualiza el markdown en el cliente (todo el
  render es server-side vía Redcarpet).
- No se toca `log_entries`, `project_associations` ni
  `project_responsibles` como controladores — su contenido de ayuda vive
  dentro de `projects.md`.

## Testing

- Test de controlador: `HelpController#show` con un topic válido
  (`projects`) responde 200 y el body contiene HTML derivado del
  markdown (ej. un `<h2>` o `<strong>`, no el `#`/`**` crudo).
- Test de controlador: topic inexistente (`no-existe`) responde 404.
- Test de seguridad: topic con path traversal (`../../../../etc/passwd`,
  URL-encodeado como corresponda para la ruta wildcard) responde 404, no
  200 con contenido de un archivo fuera de `docs/help/`.
- Test de helper/vista: una página con doc existente (ej.
  `admin/project_types#index`) renderiza el botón de ayuda contextual con
  el topic correcto; una página sin doc (ej. la pantalla de login,
  `devise/sessions#new`, que no tiene `docs/help/devise/sessions.md`) no
  lo renderiza.
- Test de la navbar: el ícono de menú de ayuda está presente en toda
  página con el usuario logueado.
