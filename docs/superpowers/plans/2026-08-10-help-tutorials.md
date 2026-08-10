# Menú de ayuda: tutoriales en Markdown por vista Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a per-view "Ayuda" button plus a central navbar help menu that render markdown tutorials (one file per controller) inside a shared Bootstrap modal.

**Architecture:** Markdown source files live at `docs/help/<controller_path>.md`. A `HelpController#show` reads and renders one via Redcarpet, cached by file mtime. The layout auto-detects whether the current page's controller has a doc file and shows a contextual "Ayuda" button; the navbar always shows a menu button listing every topic. Both trigger the same Stimulus controller, which fetches the rendered HTML and injects it into one shared modal.

**Tech Stack:** Rails 7.2, Redcarpet (new gem), Stimulus (existing pattern, see `app/javascript/controllers/theme_controller.js`), Bootstrap 5.3.3 modal (CDN, already loaded), Minitest.

## Global Constraints

- Content granularity: one `.md` file per controller (not per action) — already decided, do not split further.
- 11 topics, exact paths: `projects`, `imports`, `admin/project_types`, `admin/field_definitions`, `admin/stage_templates`, `admin/duration_profiles`, `admin/log_entry_types`, `admin/responsible_types`, `admin/responsibles`, `admin/project_type_associations`, `admin/users`.
- `log_entries`, `project_associations`, `project_responsibles` controllers get NO doc file of their own — their content lives inside `projects.md`.
- The contextual "Ayuda" button must be automatic (derived from `controller_path`), never hand-added to individual view files.
- `params[:topic]` is user-controlled input used to build a filesystem path — the controller MUST guard against path traversal by resolving with `expand_path` and verifying the result stays under `docs/help/`.
- No new JS framework or markdown-rendering library on the client — render is server-side only (Redcarpet), delivered as an HTML fragment via `fetch`.
- I18n.default_locale is `:es` — all tutorial content and UI copy ("Ayuda", "Cargando…", etc.) in Spanish.

---

### Task 1: Tutorial content (11 markdown files)

**Files:**
- Create: `docs/help/projects.md`
- Create: `docs/help/imports.md`
- Create: `docs/help/admin/project_types.md`
- Create: `docs/help/admin/field_definitions.md`
- Create: `docs/help/admin/stage_templates.md`
- Create: `docs/help/admin/duration_profiles.md`
- Create: `docs/help/admin/log_entry_types.md`
- Create: `docs/help/admin/responsible_types.md`
- Create: `docs/help/admin/responsibles.md`
- Create: `docs/help/admin/project_type_associations.md`
- Create: `docs/help/admin/users.md`

**Interfaces:**
- Produces: 11 files at the exact paths above. Task 2's controller test reads `docs/help/projects.md` as its "known good" fixture and asserts the rendered output contains an `<h2>` tag — so every file's first content line MUST be a `##`-level markdown header (not `#` or plain text), so this convention has to be consistent across all 11 files.

- [ ] **Step 1: Write `docs/help/projects.md`**

```markdown
## Proyectos

Esta es la pantalla principal de la app: la lista de todos los proyectos,
con su tipo, estado y avance.

### Crear un proyecto

Desde el botón **Nuevo proyecto** completás el tipo de proyecto y sus
datos. Las etapas del proyecto se generan automáticamente según el tipo
elegido.

### Notas de bitácora

Dentro del detalle de un proyecto podés agregar notas de bitácora
(instalación completada, incidencias, etc.) — quedan asociadas al
proyecto y a quién las escribió.

### Vincular y asociar proyectos

También desde el detalle de un proyecto podés asociarlo con otros
proyectos relacionados (por ejemplo, un proyecto de instalación con su
proyecto de mantenimiento) y asignar responsables a etapas puntuales.

### Seguimiento

El link **Seguimiento** en la barra superior muestra una vista tipo
Gantt de todos los proyectos, para ver fechas y avance de un vistazo.
```

- [ ] **Step 2: Write `docs/help/imports.md`**

```markdown
## Importar proyectos

Permite cargar muchos proyectos de una sola vez desde un archivo Excel
(.xlsx) o CSV.

### Plantilla

Descargá la plantilla desde el botón correspondiente antes de cargar
datos — tiene las columnas exactas que la app espera para el tipo de
proyecto elegido.

### Vista previa

Antes de confirmar la importación, la app te muestra una vista previa de
las filas detectadas para que revises que todo esté bien antes de
crear los proyectos.
```

- [ ] **Step 3: Write `docs/help/admin/project_types.md`**

```markdown
## Tipos de proyecto

Un tipo de proyecto define qué campos personalizados, qué etapas y qué
reglas de duración tiene cada proyecto que se cree con ese tipo.

### Duración automática vs. fechas manuales

Si un tipo de proyecto tiene activada la **duración automática**, las
fechas de cada etapa se calculan solas a partir de un perfil de
duración, en vez de que alguien las cargue a mano. Un tipo de proyecto
puede requerir fechas manuales de etapa, tener duración automática, o
ninguna de las dos cosas.

### Campos, subprocesos y perfiles de duración

Desde el detalle de un tipo de proyecto se administran sus campos
personalizados, sus subprocesos (etapas) y, si aplica, sus perfiles de
duración — ver los tutoriales de cada uno para más detalle.
```

- [ ] **Step 4: Write `docs/help/admin/field_definitions.md`**

```markdown
## Campos

Los campos personalizados son los datos propios de cada tipo de
proyecto (por ejemplo, "dirección de instalación" o "número de medidor").

### Tipo de dato

Cada campo tiene un tipo (texto, número, fecha, selección, etc.) que
determina cómo se muestra su formulario y cómo se valida.

### Orden

El orden en que aparecen los campos en el formulario del proyecto se
puede arrastrar y soltar desde la lista.
```

- [ ] **Step 5: Write `docs/help/admin/stage_templates.md`**

```markdown
## Subprocesos

Los subprocesos son las etapas por las que pasa un proyecto de un tipo
determinado (por ejemplo: "Relevamiento", "Instalación", "Certificación").

### Orden

El orden de los subprocesos define el orden en que aparecen las etapas
de cada proyecto creado con ese tipo, y se puede reordenar arrastrando.

### Fechas requeridas

Si el tipo de proyecto requiere fechas manuales de etapa, cada
subproceso necesita que alguien cargue su fecha de inicio y fin para
que el proyecto no aparezca como "pendiente de fecha".
```

- [ ] **Step 6: Write `docs/help/admin/duration_profiles.md`**

```markdown
## Perfiles de duración

Un perfil de duración define cuántos días dura cada subproceso cuando
el tipo de proyecto tiene activada la **duración automática** — así las
fechas de las etapas se calculan solas en vez de cargarse a mano.

### Cómo se aplica

Al crear o editar un proyecto con duración automática, se elige un
perfil y la app calcula las fechas de cada etapa en cadena, una después
de la otra, según los días definidos en el perfil.
```

- [ ] **Step 7: Write `docs/help/admin/log_entry_types.md`**

```markdown
## Tipos de bitácora

Definen las categorías disponibles para las notas de bitácora que se
agregan dentro del detalle de un proyecto (por ejemplo: "Nota",
"Incidencia", "Cambio de alcance").
```

- [ ] **Step 8: Write `docs/help/admin/responsible_types.md`**

```markdown
## Tipos de responsable

Definen los roles que puede tener un responsable dentro de un proyecto
(por ejemplo: "Instalador", "Supervisor"). Se usan al asignar
responsables a etapas puntuales de un proyecto.
```

- [ ] **Step 9: Write `docs/help/admin/responsibles.md`**

```markdown
## Responsables

La lista de personas o equipos que pueden asignarse como responsables
de proyectos o de etapas puntuales. Un responsable puede estar vinculado
a un usuario de la app (para que vea solo lo que le corresponde) o ser
solo un nombre de referencia.
```

- [ ] **Step 10: Write `docs/help/admin/project_type_associations.md`**

```markdown
## Tipos de asociación

Definen qué combinaciones de tipos de proyecto pueden vincularse entre
sí (por ejemplo, que un proyecto de "Instalación" pueda asociarse a uno
de "Mantenimiento"). Sin una asociación configurada acá, esos dos tipos
de proyecto no van a aparecer como opción para vincular en el detalle de
un proyecto.
```

- [ ] **Step 11: Write `docs/help/admin/users.md`**

```markdown
## Usuarios

Administración de las cuentas de acceso a la app.

### Rol

Cada usuario tiene un rol (Administrador, Gerente, Visor, Responsable)
que determina qué puede ver y editar.

### Accesos puntuales

Además del rol, a un usuario Visor o Gerente se le puede dar acceso de
ver/editar a tipos de proyecto o proyectos individuales puntuales, desde
la sección de accesos en el detalle del usuario.

### Cambiar contraseña

Dejar el campo de contraseña en blanco al editar un usuario mantiene su
contraseña actual sin cambios.
```

- [ ] **Step 12: Verify all 11 files exist and are non-empty**

Run: `find docs/help -name "*.md" | wc -l` — expected: `11`
Run: `for f in $(find docs/help -name "*.md"); do [ -s "$f" ] || echo "EMPTY: $f"; done` — expected: no output.

- [ ] **Step 13: Commit**

```bash
git add docs/help
git commit -m "Agregar contenido de tutoriales de ayuda en Markdown"
```

---

### Task 2: `HelpController`, route, and Redcarpet rendering

**Files:**
- Modify: `Gemfile`
- Modify: `config/routes.rb`
- Create: `app/controllers/help_controller.rb`
- Test: `test/controllers/help_controller_test.rb`

**Interfaces:**
- Consumes: `docs/help/projects.md` from Task 1 as the "known good" topic fixture.
- Produces: `GET /help/*topic` (route name `help_topic_path(topic)`), returning a layout-less HTML fragment (200) for a valid topic, or a bare 404 for anything else — this is what Task 3/4's Stimulus controller fetches.

- [ ] **Step 1: Add the gem**

In `Gemfile`, add near the other content-handling gems (after the `caxlsx` line):

```ruby
# Renders the Markdown tutorial files under docs/help/ for the in-app help modal.
gem "redcarpet"
```

Run: `bundle install`
Expected: `redcarpet (3.6.1)` (already present in the local gem cache) added to `Gemfile.lock`, install succeeds without network access.

- [ ] **Step 2: Add the route**

In `config/routes.rb`, add right after `devise_for :users, skip: [:registerable]`:

```ruby
  get "help/*topic", to: "help#show", as: :help_topic
```

- [ ] **Step 3: Write the failing tests**

Create `test/controllers/help_controller_test.rb`:

```ruby
require "test_helper"

class HelpControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:juan) }

  test "show renders a known topic's markdown as HTML" do
    get help_topic_path(topic: "projects")
    assert_response :success
    assert_match "<h2>", @response.body
    assert_match "Proyectos", @response.body
  end

  test "show 404s for an unknown topic" do
    get help_topic_path(topic: "no-existe")
    assert_response :not_found
  end

  test "show 404s on path traversal instead of leaking files outside docs/help" do
    get "/help/..%2F..%2F..%2F..%2F..%2Fetc%2Fpasswd"
    assert_response :not_found
  end

  test "show renders a nested admin topic" do
    get help_topic_path(topic: "admin/project_types")
    assert_response :success
    assert_match "Tipos de proyecto", @response.body
  end
end
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `bin/rails test test/controllers/help_controller_test.rb`
Expected: FAIL — `NameError`/routing error, `help_topic_path` doesn't exist yet (route not added) or `HelpController` doesn't exist.

- [ ] **Step 5: Write `HelpController`**

Create `app/controllers/help_controller.rb`:

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

- [ ] **Step 6: Run tests to verify they pass**

Run: `bin/rails test test/controllers/help_controller_test.rb`
Expected: PASS (4/4)

- [ ] **Step 7: Run the full suite**

Run: `bin/rails test`
Expected: 0 failures, 0 errors — confirms adding the gem/route didn't break anything else.

- [ ] **Step 8: Commit**

```bash
git add Gemfile Gemfile.lock config/routes.rb app/controllers/help_controller.rb test/controllers/help_controller_test.rb
git commit -m "Agregar HelpController: renderiza tutoriales Markdown vía Redcarpet"
```

---

### Task 3: Contextual "Ayuda" button, shared modal, and Stimulus controller

**Files:**
- Modify: `app/helpers/application_helper.rb`
- Modify: `app/views/layouts/application.html.erb`
- Create: `app/javascript/controllers/help_controller.js`
- Modify: `app/assets/stylesheets/application.css`
- Test: `test/helpers/application_helper_test.rb`
- Test: `test/controllers/help_button_test.rb`

**Interfaces:**
- Consumes: `GET /help/*topic` (Task 2, via `help_topic_path`).
- Produces: `help_topic_path_if_exists` helper (returns a topic string or `nil`) — Task 4's navbar menu doesn't call this directly (it always shows every topic), but reuses the same `data-controller="help"` / `data-action="click->help#open"` / `data-help-topic-value="..."` markup convention this task establishes, and the same `#help-modal` this task creates.

- [ ] **Step 1: Write the failing helper test**

Add to `test/helpers/application_helper_test.rb`:

```ruby
  test "help_topic_path_if_exists returns the controller path when a doc file exists" do
    @controller.stub(:controller_path, "projects") do
      assert_equal "projects", help_topic_path_if_exists
    end
  end

  test "help_topic_path_if_exists returns nil when no doc file exists for the controller" do
    @controller.stub(:controller_path, "devise/sessions") do
      assert_nil help_topic_path_if_exists
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/helpers/application_helper_test.rb -n "/help_topic_path_if_exists/"`
Expected: FAIL — `NoMethodError: undefined method 'help_topic_path_if_exists'`

- [ ] **Step 3: Add the helper method**

In `app/helpers/application_helper.rb`, add inside the `ApplicationHelper` module (after `format_change_value`, before the closing `end`):

```ruby
  def help_topic_path_if_exists
    Rails.root.join("docs", "help", "#{controller_path}.md").exist? ? controller_path : nil
  end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/helpers/application_helper_test.rb -n "/help_topic_path_if_exists/"`
Expected: PASS (2/2)

- [ ] **Step 5: Write the failing integration test for the button's visibility**

Create `test/controllers/help_button_test.rb`:

```ruby
require "test_helper"

class HelpButtonTest < ActionDispatch::IntegrationTest
  test "a page with a doc file shows the contextual help button with the right topic" do
    sign_in users(:juan)
    get admin_project_types_path
    assert_response :success
    assert_select "button[data-help-topic-value=?]", "admin/project_types"
  end

  test "a page without a doc file does not show the contextual help button" do
    get new_user_session_path
    assert_response :success
    assert_select "button[data-controller=?]", "help", count: 0
  end
end
```

- [ ] **Step 6: Run test to verify it fails**

Run: `bin/rails test test/controllers/help_button_test.rb`
Expected: FAIL — no `data-help-topic-value` attribute anywhere yet (button doesn't exist).

- [ ] **Step 7: Add the shared modal and contextual button to the layout**

In `app/views/layouts/application.html.erb`, replace:

```erb
  <body>
    <%= render "layouts/navbar" %>
    <div class="container py-4">
      <% if notice %>
        <div class="alert alert-success"><%= notice %></div>
      <% end %>
      <% if alert %>
        <div class="alert alert-danger"><%= alert %></div>
      <% end %>
      <%= yield %>
    </div>
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/tom-select@2.3.1/dist/js/tom-select.complete.min.js"></script>
  </body>
```

with:

```erb
  <body>
    <%= render "layouts/navbar" %>
    <div class="container py-4">
      <% if notice %>
        <div class="alert alert-success"><%= notice %></div>
      <% end %>
      <% if alert %>
        <div class="alert alert-danger"><%= alert %></div>
      <% end %>
      <% if (topic = help_topic_path_if_exists) %>
        <div class="text-end mb-2">
          <button type="button" class="btn btn-sm btn-outline-secondary" data-controller="help" data-action="click->help#open" data-help-topic-value="<%= topic %>">
            <i class="bi bi-question-circle"></i> Ayuda
          </button>
        </div>
      <% end %>
      <%= yield %>
    </div>

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

    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/tom-select@2.3.1/dist/js/tom-select.complete.min.js"></script>
  </body>
```

- [ ] **Step 8: Add the Stimulus controller**

Create `app/javascript/controllers/help_controller.js`:

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

`app/javascript/controllers/index.js` uses `stimulus-loading`'s `eagerLoadControllersFrom`/pin-all convention (see `config/importmap.rb:4`, `pin_all_from "app/javascript/controllers", under: "controllers"`) — no manual registration needed, the new file is picked up automatically the same way `theme_controller.js` already is.

- [ ] **Step 9: Add minimal modal-body styling**

In `app/assets/stylesheets/application.css`, append:

```css
.modal-body h2 {
  font-size: 1.25rem;
  font-weight: 600;
  margin-top: 0;
}

.modal-body h3 {
  font-size: 1.05rem;
  font-weight: 600;
  color: var(--bs-primary);
  margin-top: 1.25rem;
}

.modal-body :last-child {
  margin-bottom: 0;
}
```

- [ ] **Step 10: Run tests to verify they pass**

Run: `bin/rails test test/controllers/help_button_test.rb`
Expected: PASS (2/2)

- [ ] **Step 11: Run the full suite**

Run: `bin/rails test`
Expected: 0 failures, 0 errors.

- [ ] **Step 12: Commit**

```bash
git add app/helpers/application_helper.rb app/views/layouts/application.html.erb app/javascript/controllers/help_controller.js app/assets/stylesheets/application.css test/helpers/application_helper_test.rb test/controllers/help_button_test.rb
git commit -m "Agregar botón de ayuda contextual, modal compartido y controller de Stimulus"
```

---

### Task 4: Central help menu in the navbar

**Files:**
- Modify: `app/helpers/application_helper.rb`
- Modify: `app/views/layouts/_navbar.html.erb`
- Test: `test/controllers/navbar_test.rb`

**Interfaces:**
- Consumes: `#help-modal` and the `help` Stimulus controller from Task 3 (same `data-controller="help"` / `data-action="click->help#open"` / `data-help-topic-value="..."` convention — no new JS).
- Produces: `HELP_MENU` constant on `ApplicationHelper`, used only by the navbar partial.

- [ ] **Step 1: Write the failing test**

Add to `test/controllers/navbar_test.rb` (inside the existing `NavbarTest` class):

```ruby
  test "navbar includes the help menu with every topic" do
    sign_in users(:juan)
    get root_path
    follow_redirect!
    assert_response :success
    assert_select "#help-menu-modal button[data-help-topic-value=?]", "projects"
    assert_select "#help-menu-modal button[data-help-topic-value=?]", "admin/users"
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/navbar_test.rb -n "/help menu/"`
Expected: FAIL — no element with `id="help-menu-modal"` exists yet.

- [ ] **Step 3: Add the `HELP_MENU` constant**

In `app/helpers/application_helper.rb`, add near the other constants at the top of the `ApplicationHelper` module:

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

- [ ] **Step 4: Add the navbar icon and menu modal**

In `app/views/layouts/_navbar.html.erb`, add the menu-trigger button right before the existing theme-toggle button (inside `<div class="navbar-nav" data-controller="theme">`):

```erb
    <div class="navbar-nav" data-controller="theme">
      <button type="button" class="btn btn-outline-secondary btn-sm me-2" data-bs-toggle="modal" data-bs-target="#help-menu-modal" aria-label="Ayuda">
        <i class="bi bi-question-circle"></i>
      </button>
      <button type="button" class="btn btn-outline-secondary btn-sm me-2" data-action="click->theme#toggle" aria-label="Cambiar tema claro/oscuro">
        <span data-theme-target="icon">☾</span>
      </button>
```

(only the new `<button>` block is added; the existing theme button and everything below it stays exactly as-is.)

Then, at the end of the same file (`app/views/layouts/_navbar.html.erb`), append the menu modal:

```erb
<div class="modal fade" id="help-menu-modal" tabindex="-1">
  <div class="modal-dialog modal-dialog-scrollable">
    <div class="modal-content">
      <div class="modal-header">
        <h5 class="modal-title">Ayuda</h5>
        <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
      </div>
      <div class="modal-body">
        <% ApplicationHelper::HELP_MENU.each do |group| %>
          <h6 class="text-muted text-uppercase small mt-2 mb-2"><%= group[:section] %></h6>
          <div class="list-group mb-3">
            <% group[:items].each do |label, topic| %>
              <button type="button" class="list-group-item list-group-item-action" data-bs-dismiss="modal" data-controller="help" data-action="click->help#open" data-help-topic-value="<%= topic %>">
                <%= label %>
              </button>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
  </div>
</div>
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bin/rails test test/controllers/navbar_test.rb`
Expected: PASS, all tests in the file including the new one.

- [ ] **Step 6: Run the full suite**

Run: `bin/rails test`
Expected: 0 failures, 0 errors.

- [ ] **Step 7: Commit**

```bash
git add app/helpers/application_helper.rb app/views/layouts/_navbar.html.erb test/controllers/navbar_test.rb
git commit -m "Agregar menú central de ayuda en la navbar"
```

---

### Task 5: Full suite verification

**Files:** none (verification only)

- [ ] **Step 1: Run the full test suite**

Run: `bin/rails test`
Expected: 0 failures, 0 errors — confirms Tasks 1-4 together don't regress anything (Devise flows, admin controllers, Gantt views, etc.).

- [ ] **Step 2: Manual smoke check**

Start the app (`bin/rails server` or however this project is normally run locally) and, signed in as an existing user:
- Visit `/admin/project_types` — confirm the "Ayuda" button appears above the panel and opens a modal with the "Tipos de proyecto" tutorial rendered (headings styled, not raw `##`/`**`).
- Visit `/projects` (or root) — confirm the navbar's "?" icon opens the topic-list modal, and clicking "Proyectos" in that list opens the same content modal with the projects tutorial.
- Visit the sign-in page while logged out — confirm no contextual "Ayuda" button appears (no doc for `devise/sessions`), but note the navbar itself isn't shown to anonymous visitors either way (matches existing app behavior).

- [ ] **Step 3: Commit any fixups**

If Step 1 or 2 surfaced issues, commit fixes individually with a message describing what broke and why.
