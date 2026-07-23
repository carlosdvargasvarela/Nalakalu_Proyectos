# Pantalla de inicio unificada, Gantt de solo lectura y app 100% en español — design

## Contexto

Tras cerrar el CRUD de instaladores/archivado/tabla de etapas, el usuario señaló tres problemas de UX que hacen que la app no reemplace todavía al Excel: (1) hay que saltar entre "Proyectos" (lista CRUD) y "Gerencia" (Gantt filtrable) para ver lo mismo desde dos ángulos; (2) los Gantt son arrastrables aunque la edición real ocurre en la tabla de etapas, lo que invita a un gesto que no persiste nada; (3) partes de la interfaz siguen en inglés — específicamente las pantallas de Devise (login/registro), que nunca se tradujeron.

Investigación técnica relevante (confirmada leyendo el bundle real servido por jsDelivr/unpkg de `frappe-gantt@0.6.1`, idéntico en ambos CDNs):
- La librería no tiene un modo `readonly` nativo. Los eventos disponibles son `on_click`, `on_date_change`, `on_progress_change`, `on_view_change`, invocados dinámicamente vía `options["on_" + evento]` — por eso `on_click` ya funciona hoy aunque no aparezca como texto literal en el bundle minificado.
- Soporta `language` con tablas de meses integradas para varios idiomas, incluyendo `"es"`.
- `Installer` no es una relación directa de `Project` — es un campo `custom_fields` dinámico (`reference_table: "installers"`), hoy con la clave `"instalador"` en el único `ProjectType` sembrado ("Instalaciones").
- Devise está configurado con módulos `database_authenticatable, registerable, rememberable, validatable` (sin `recoverable`/`confirmable`) — por lo tanto las únicas vistas de Devise alcanzables son `sessions/new`, `registrations/new`, `registrations/edit`, y los parciales compartidos `shared/_links` y `shared/_error_messages`. Estas vistas del gem (`devise-5.0.4`) tienen texto en inglés **hardcodeado** ("Log in", "Sign up", etc.) — no usan `t()`, así que agregar solo un archivo de locale no las traduce; hay que generarlas (`rails g devise:views`) y reemplazar el texto directamente.
- Los mensajes de flash/mailer de Devise (`devise.en.yml`) y los mensajes genéricos de validación de ActiveRecord (`blank`, `taken`, etc., usados tanto por `User` como por los modelos propios sin `:message` explícito) sí pasan por `I18n.t` y sí se traducen con un archivo de locale.

## Alcance

1. **Pantalla de inicio unificada** — fusiona `projects#index` (tabla CRUD) y `projects#dashboard` (Gantt filtrable) en una sola acción `projects#index`: filtros (Tipo, Estado, Instalador) → Gantt de solo lectura → tabla con acciones (Editar/Archivar). Se elimina la ruta `/projects/dashboard`, su vista y el link "Gerencia" del navbar.
2. **Filtro por Instalador** en esa misma pantalla.
3. **Gantt de solo lectura + en español** — aplica a la pantalla de inicio (fusionada) y a `projects#show`.
4. **Devise en español** — vistas de sesión/registro con texto en español (hardcodeado, no vía `t()`, porque solo hay un idioma — YAGNI de una capa de traducción para un solo idioma).
5. **Mensajes de validación en español** — `default_locale: :es`, `devise.es.yml` (traducción mecánica de `devise.en.yml`), `es.yml` con las claves genéricas de ActiveRecord que la app realmente dispara (`blank`, `taken`, `invalid`, `too_short`, `confirmation`, `inclusion`) y nombres de atributo humanizados (email, password, name, slug, etc.). Se borra la clave `hello` de `en.yml` (dead code, sin referencias en el código — confirmado por grep).

Fuera de alcance: pulido visual/CSS (Ronda 2, a discutir por separado), soporte multi-idioma real (solo se traduce a español, sin infraestructura de cambio de idioma), traducir vistas de `confirmable`/`recoverable`/`lockable` (esos módulos de Devise no están habilitados en `User`), cobertura exhaustiva de *todas* las claves posibles de `errors.messages` de Rails (solo las que la app dispara hoy — ver nota en el archivo de locale).

## 1. Pantalla de inicio unificada

**Ruta:** se elimina `get "projects/dashboard", to: "projects#dashboard", as: :dashboard_projects` de `config/routes.rb`. `resources :projects` queda igual (ya no anida `project_stages` desde la Ronda anterior).

**Controlador** (`ProjectsController`, reemplaza `index` y elimina `dashboard`):

```ruby
def index
  @project_types = ProjectType.all
  @statuses = Project.distinct.pluck(:status).compact
  @installers = Installer.all
  @projects = Project.includes(:project_type, project_stages: :stage_template)
  @projects = params[:status].present? ? @projects.where(status: params[:status]) : @projects.where.not(status: "archived")
  @projects = @projects.where(project_type_id: params[:project_type_id]) if params[:project_type_id].present?
  @projects = filter_by_installer(@projects, params[:installer_id]) if params[:installer_id].present?
end
```

(El orden importa: si no se elige un Estado explícito, se excluyen los archivados — igual que el comportamiento actual del índice. Si se elige un Estado, ese filtro manda, incluyendo `"archived"` — igual que el comportamiento actual de Gerencia.)

`filter_by_installer` (método privado nuevo):

```ruby
def filter_by_installer(scope, installer_id)
  keys = FieldDefinition.where(reference_table: "installers").distinct.pluck(:key)
  return scope.none if keys.empty?
  keys.map { |key| scope.where("custom_fields ->> ? = ?", key, installer_id.to_s) }.reduce(:or)
end
```

(`custom_fields ->> ?` con el nombre de la clave como parámetro ligado es seguro — Postgres acepta cualquier expresión de texto como operando derecho de `->>`, no hace falta interpolar el nombre de la clave en el SQL. No se hardcodea `"instalador"`: si en el futuro otro `ProjectType` tiene su propio campo `reference_table: "installers"` con otra clave, el filtro ya lo cubre.)

**Vista** (`app/views/projects/index.html.erb`, reemplaza tanto el `index` actual como `dashboard.html.erb`, que se borra):

1. Filtros — `form_with url: projects_path, method: :get` con tres `<select>`: Tipo (`@project_types`), Estado (`@statuses`), Instalador (`@installers`), todos con `include_blank: "Todos"` y `selected:` desde `params`.
2. Gantt de solo lectura (si `@projects.any?`) — mismo patrón que el `dashboard.html.erb` actual (un task por proyecto, `gantt_window`, `current_stage` para el color), pero con las opciones de la sección 3 (`language: "es"`, `on_date_change`/`on_progress_change`).
3. Tabla de acciones — el `<table>` que hoy tiene `index.html.erb` (Nombre/Tipo/Estado/Editar/Archivar), debajo del Gantt.
4. "Nuevo proyecto" — la lista de tipos de proyecto que hoy tiene `index.html.erb`, al final, sin cambios.
5. Mensaje "No hay proyectos con estos filtros" si `@projects.none?` (reemplaza el Gantt y la tabla cuando no hay resultados).

**Nav** (`app/views/layouts/_navbar.html.erb`): se elimina el link "Gerencia" (`dashboard_projects_path`). El link "Proyectos" (`projects_path`) queda como estaba — sigue siendo la puerta de entrada, ahora con todo junto.

## 2. Filtro por Instalador

Ya cubierto en la sección 1 (`@installers`, el `<select>`, y `filter_by_installer`). El `<select>` usa `installer.name` como texto y `installer.id` como value, igual patrón que los otros dos filtros.

## 3. Gantt de solo lectura + en español

Aplica en dos vistas: la nueva `projects/index.html.erb` (sección 1) y `projects/show.html.erb` (ya existente, solo se ajustan las opciones de construcción). En ambas, el bloque `new Gantt(...)` pasa a:

```js
new Gantt("#gantt", tasks, {
  language: "es",
  on_click: function (task) { /* ya existente en cada vista, sin cambios */ },
  on_date_change: function () {
    gantt.refresh(tasks);
  },
  on_progress_change: function () {
    gantt.refresh(tasks);
  }
});
```

(`gantt.refresh(tasks)` redibuja con el array `tasks` original — que nunca se muta — anulando visualmente cualquier arrastre apenas termina. No hace falta CSS ni bloquear el `mousedown`: el usuario puede intentar arrastrar, pero la barra vuelve a su lugar al soltar. La variable local `gantt` debe capturarse (`var gantt = new Gantt(...)`) para poder llamarla desde dentro de sus propios callbacks.)

Nota de implementación: en `projects/index.html.erb` la variable JS debe llamarse distinto a la de `projects/show.html.erb` si alguna vez comparten contexto (no lo hacen — son páginas distintas), así que no hay conflicto de nombres entre vistas.

## 4. Devise en español

```bash
bin/rails generate devise:views
```

Esto copia las vistas del gem a `app/views/devise/`. Solo se edita el texto de las que son alcanzables (ver Contexto): `sessions/new.html.erb`, `registrations/new.html.erb`, `registrations/edit.html.erb`, `shared/_links.html.erb`, `shared/_error_messages.html.erb`. El resto de las vistas generadas (`confirmations/`, `passwords/`, `unlocks/`, mailer views) se **borran** — no son alcanzables con los módulos habilitados en `User`, y dejarlas sin traducir/sin usar es ruido (ponytail: deletion over addition).

Ejemplo de traducción directa (sin `t()`, un solo idioma — `sessions/new.html.erb`):

```erb
<h2>Iniciar sesión</h2>

<%= form_for(resource, as: resource_name, url: session_path(resource_name)) do |f| %>
  <div class="field">
    <p><%= f.label :email, "Correo electrónico" %></p>
    <p><%= f.email_field :email, autofocus: true, autocomplete: "email" %></p>
  </div>

  <div class="field">
    <p><%= f.label :password, "Contraseña" %></p>
    <p><%= f.password_field :password, autocomplete: "current-password" %></p>
  </div>

  <% if devise_mapping.rememberable? %>
    <div class="field">
      <p><%= f.check_box :remember_me %></p>
      <p><%= f.label :remember_me, "Recordarme" %></p>
    </div>
  <% end %>

  <div class="actions">
    <%= f.submit "Iniciar sesión" %>
  </div>
<% end %>

<%= render "devise/shared/links" %>
```

Mismo criterio (reemplazo directo de cadenas en inglés por español) para `registrations/new.html.erb` ("Regístrate" / "Registrarse"), `registrations/edit.html.erb` ("Editar cuenta" / campos de contraseña actual / "Actualizar" / "Cancelar mi cuenta"), `shared/_links.html.erb` ("Iniciar sesión" / "Regístrate" en lugar de "Log in"/"Sign up"), y `shared/_error_messages.html.erb` ("Se han encontrado N errores:" en lugar de "N error(s) prohibited...").

## 5. Mensajes de validación en español

`config/application.rb`, dentro de la clase `Application`:

```ruby
config.i18n.default_locale = :es
```

`config/locales/es.yml` (nuevo):

```yaml
es:
  activerecord:
    errors:
      messages:
        blank: "no puede estar en blanco"
        taken: "ya está en uso"
        invalid: "no es válido"
        too_short: "es demasiado corto (mínimo %{count} caracteres)"
        confirmation: "no coincide con %{attribute}"
        inclusion: "no está incluido en la lista"
    attributes:
      user:
        email: "Correo electrónico"
        password: "Contraseña"
        password_confirmation: "Confirmación de contraseña"
      project_type:
        name: "Nombre"
        slug: "Slug"
      field_definition:
        key: "Clave"
        label: "Etiqueta"
        data_type: "Tipo de dato"
      stage_template:
        name: "Nombre"
        color: "Color"
      project:
        name: "Nombre"
      project_stage:
        name: "Nombre"
        progress_percent: "Porcentaje de avance"
      installer:
        name: "Nombre"
```

(Nota `ponytail:` en el propio archivo — cubre solo las claves de `errors.messages` que la app realmente dispara hoy; si un modelo nuevo agrega un validador con un mensaje genérico no listado aquí, ese mensaje concreto aparecerá en inglés hasta que se agregue su clave. No se persigue cobertura exhaustiva de todas las claves posibles de Rails/ActiveRecord.)

`config/locales/devise.es.yml` (nuevo): misma estructura que `devise.en.yml`, con cada valor traducido al español (traducción mecánica, sin cambios de claves ni de interpolaciones `%{...}`).

`config/locales/en.yml`: se borra la clave `hello: "Hello world"` (confirmado sin referencias en el código vía `grep -rn '"hello"' app/`) — si el archivo queda vacío de contenido útil, se borra el archivo completo también.

## Testing

- Controlador: `ProjectsController#index` — sin filtros (todos los activos, Gantt presente), filtrado por tipo, por estado (incluyendo `"archived"`), por instalador, combinación de filtros, mensaje cuando no hay resultados, tabla de acciones (Editar/Archivar) presente, Gantt ausente cuando `@projects` está vacío.
- Controlador: filtro por instalador — un proyecto con `custom_fields["instalador"] = installer.id` aparece al filtrar por ese instalador; un proyecto con otro instalador (o sin instalador) no aparece.
- Se retiran los tests de `ProjectsController#dashboard` (la acción ya no existe) y se adaptan sus aserciones al nuevo `index` fusionado.
- `NavbarTest`: se retira el test "navbar includes a link to the management dashboard" (ruta eliminada).
- No hay test automatizado para el comportamiento de arrastre del Gantt (JS puro, fuera del alcance de Minitest) ni para el idioma de los meses del Gantt (interno a la librería) — se verifica manualmente.
- No hay test automatizado para el texto exacto de las vistas de Devise generadas (fuera del flujo de request habitual de la suite) — se verifica manualmente iniciando sesión/registrándose y confirmando que el texto está en español.

## Edge cases

- Ningún `FieldDefinition` con `reference_table: "installers"` (caso hipotético si se borra ese campo desde el admin): `filter_by_installer` devuelve `scope.none` en vez de romper — el filtro simplemente no encuentra nada, no lanza excepción.
- Un proyecto sin ningún stage (mismo edge case ya cubierto en specs previos): la nueva pantalla de inicio maneja esto igual que `show.html.erb` ya lo hacía — `gantt_window` cae al fallback de una semana.
- Selección de Estado = "archived" sigue mostrando esos proyectos en el Gantt/tabla de la pantalla de inicio (comportamiento intencional, igual que la Gerencia actual) — no es una regresión del archivado agregado en la Ronda anterior.
- Arrastrar una barra del Gantt y soltar fuera del área visible del gráfico: `on_date_change`/`on_progress_change` igual disparan al soltar (evento del navegador, no depende de la posición final), así que `gantt.refresh(tasks)` corre y la barra vuelve a su lugar sin importar dónde se soltó.
