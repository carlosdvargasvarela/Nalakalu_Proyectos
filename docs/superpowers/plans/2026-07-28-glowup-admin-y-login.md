# Glowup de login y panel admin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Visually polish the login page and every `/admin/*` view (project types, field definitions, stage templates, log entry types, installers, users) with consistent Bootstrap cards, without changing any behavior, existing color scheme, or test contracts.

**Architecture:** A single `admin_card(title) { ... }` helper in `ApplicationHelper` wraps each currently-bare `<h1> + content` view in a Bootstrap card. Two lines of global CSS give all cards (including the ones that already exist) a subtle shadow. The login page gets a one-off centered-card treatment (not worth a shared helper for a single view). Purely presentational — no controller, model, route, or test-behavior changes.

**Tech Stack:** Rails 7.2.3, Bootstrap 5.3.3 (via CDN, already in the layout), ERB, Minitest.

## Global Constraints

- No new color palette, no new fonts, no new dependencies — same `--bs-primary: #2c3e50` theme already in `app/assets/stylesheets/application.css`.
- `admin/project_types/show.html.erb` is NOT touched (it already has cards; it only benefits from the new global `.card` CSS).
- The login page's `<h2>Iniciar sesión</h2>` and the submit button's `"Iniciar sesión"` text must be preserved exactly — `test/controllers/authentication_test.rb`'s `"sign-in page is in Spanish"` test asserts on both.
- No existing form field, label, or button text changes anywhere — only the wrapping structure around them.
- Ponytail discipline throughout: reuse the existing `STATUS_BADGE_CLASSES`/`status_badge` pattern already in `ApplicationHelper` for the new role badge, don't invent a new styling mechanism.

---

### Task 1: `admin_card` helper, global CSS, login page

**Files:**
- Modify: `app/helpers/application_helper.rb`
- Modify: `app/assets/stylesheets/application.css`
- Modify: `app/views/devise/sessions/new.html.erb`
- Test: `test/controllers/authentication_test.rb`

**Interfaces:**
- Produces: `admin_card(title, &block)` — a view helper every other task's views call. Must be built and verified working (via the login page's own card, and later a quick admin-page smoke test) before Task 2+ depend on it.

- [ ] **Step 1: Add the `admin_card` helper**

Read `app/helpers/application_helper.rb` first (shown in full above in this plan's context — it currently ends with `format_change_value`). Add, before the final `end`:

```ruby
  def admin_card(title, &block)
    content_tag(:div, class: "card shadow-sm mb-4") do
      content_tag(:div, title, class: "card-header fw-semibold") +
        content_tag(:div, capture(&block), class: "card-body")
    end
  end
```

- [ ] **Step 2: Add the global CSS**

Read `app/assets/stylesheets/application.css` first. Append at the end of the file:

```css
.card {
  box-shadow: 0 0.125rem 0.5rem rgba(0, 0, 0, 0.06);
  border: 1px solid rgba(0, 0, 0, 0.06);
}

.card-header {
  background-color: #f8f9fa;
  font-weight: 600;
}
```

- [ ] **Step 3: Rewrite the login page**

Read `app/views/devise/sessions/new.html.erb` first (shown in full above). Replace its entire contents with:

```erb
<div class="row justify-content-center">
  <div class="col-md-5 col-lg-4">
    <div class="card shadow-sm mt-5">
      <div class="card-body p-4">
        <div class="text-center mb-4">
          <i class="bi bi-person-circle" style="font-size: 2.5rem; color: var(--bs-primary);"></i>
          <h2 class="h4 mt-2 mb-0">Iniciar sesión</h2>
        </div>

        <%= form_for(resource, as: resource_name, url: session_path(resource_name)) do |f| %>
          <div class="mb-3">
            <%= f.label :email, "Correo electrónico", class: "form-label" %>
            <%= f.email_field :email, autofocus: true, autocomplete: "email", class: "form-control" %>
          </div>

          <div class="mb-3">
            <%= f.label :password, "Contraseña", class: "form-label" %>
            <%= f.password_field :password, autocomplete: "current-password", class: "form-control" %>
          </div>

          <% if devise_mapping.rememberable? %>
            <div class="form-check mb-3">
              <%= f.check_box :remember_me, class: "form-check-input" %>
              <%= f.label :remember_me, "Recordarme", class: "form-check-label" %>
            </div>
          <% end %>

          <%= f.submit "Iniciar sesión", class: "btn btn-primary w-100" %>
        <% end %>
      </div>
    </div>
  </div>
</div>
```

Note: the old file also rendered `<%= render "devise/shared/links" %>` at the bottom. Do NOT keep that render call — `devise/shared/_links.html.erb` only ever showed a "Regístrate" link when `devise_mapping.registerable?` (false now, `:registerable` was removed) and an "Iniciar sesión" link hidden on the sessions controller itself (`controller_name != 'sessions'`, always false here) — on this page it already rendered nothing visible. Dropping the render call removes a no-op include, not a feature.

- [ ] **Step 4: Run the existing authentication test to verify the contract holds**

```bash
bin/rails test test/controllers/authentication_test.rb
```
Expected: PASS (4 tests) — `"sign-in page is in Spanish"` still finds `<h2>Iniciar sesión</h2>` and the `"Iniciar sesión"`-valued submit input.

- [ ] **Step 5: Run the full suite**

```bash
bin/rails test
```
Expected: PASS, 0 failures, 0 errors — no other test touches the login page's markup or any admin view yet (Tasks 2-4 haven't run).

- [ ] **Step 6: Commit**

```bash
git add app/helpers/application_helper.rb app/assets/stylesheets/application.css app/views/devise/sessions/new.html.erb
git commit -m "Add admin_card helper, card shadow CSS, and glow up the login page"
```

---

### Task 2: `project_types`, `field_definitions`, `stage_templates` views

**Files:**
- Modify: `app/views/admin/project_types/index.html.erb`
- Modify: `app/views/admin/project_types/new.html.erb`
- Modify: `app/views/admin/project_types/edit.html.erb`
- Modify: `app/views/admin/project_types/_form.html.erb`
- Modify: `app/views/admin/field_definitions/new.html.erb`
- Modify: `app/views/admin/field_definitions/edit.html.erb`
- Modify: `app/views/admin/field_definitions/_form.html.erb`
- Modify: `app/views/admin/stage_templates/new.html.erb`
- Modify: `app/views/admin/stage_templates/edit.html.erb`
- Modify: `app/views/admin/stage_templates/_form.html.erb`
- Test: `test/controllers/admin/project_types_controller_test.rb`, `test/controllers/admin/field_definitions_controller_test.rb`, `test/controllers/admin/stage_templates_controller_test.rb`

**Interfaces:**
- Consumes: `admin_card` (Task 1).

**Note:** `admin/project_types/show.html.erb` is explicitly OUT of scope for this task (and the whole plan) — it already has cards; don't touch it.

- [ ] **Step 1: Run the three existing test files to record the current-passing baseline**

```bash
bin/rails test test/controllers/admin/project_types_controller_test.rb test/controllers/admin/field_definitions_controller_test.rb test/controllers/admin/stage_templates_controller_test.rb
```
Expected: PASS (baseline — these should already pass before you touch anything; if any fail here, stop and report BLOCKED, something's wrong before you've even started).

- [ ] **Step 2: `project_types/index.html.erb`**

Read the current file (shown in full in the design spec / earlier context: a bare `<h1>Tipos de proyecto</h1>` + two buttons + a `<ul class="list-group">`). Replace with:

```erb
<%= admin_card("Tipos de proyecto") do %>
  <%= link_to "Nuevo tipo de proyecto", new_admin_project_type_path, class: "btn btn-primary mb-3" %>
  <%= link_to "Instaladores", admin_installers_path, class: "btn btn-outline-secondary mb-3" %>
  <ul class="list-group">
    <% @project_types.each do |project_type| %>
      <li class="list-group-item"><%= link_to project_type.name, admin_project_type_path(project_type) %></li>
    <% end %>
  </ul>
<% end %>
```

- [ ] **Step 3: `project_types/_form.html.erb`, `new.html.erb`, `edit.html.erb`**

Read all three current files first. Replace `_form.html.erb`'s contents with (wrapping the existing `form_with` block, unchanged inside, in `admin_card`):

```erb
<%= admin_card(project_type.persisted? ? "Editar tipo de proyecto" : "Nuevo tipo de proyecto") do %>
  <%= form_with model: [:admin, project_type] do |form| %>
    <% if project_type.errors.any? %>
      <div class="alert alert-danger">
        <ul class="mb-0">
          <% project_type.errors.full_messages.each do |message| %>
            <li><%= message %></li>
          <% end %>
        </ul>
      </div>
    <% end %>

    <div class="mb-3">
      <%= form.label :name, class: "form-label" %>
      <%= form.text_field :name, class: "form-control" %>
    </div>
    <div class="mb-3">
      <%= form.label :slug, class: "form-label" %>
      <%= form.text_field :slug, class: "form-control" %>
    </div>
    <%= form.submit class: "btn btn-primary" %>
  <% end %>
<% end %>
```

Replace `new.html.erb` with just:
```erb
<%= render "form", project_type: @project_type %>
```

Replace `edit.html.erb` with just:
```erb
<%= render "form", project_type: @project_type %>
```

- [ ] **Step 4: `field_definitions/_form.html.erb`, `new.html.erb`, `edit.html.erb`**

Read all three current files first. Replace `_form.html.erb`'s contents (wrap the existing `form_with` block, contents unchanged, in `admin_card` — title needs the `project_type` name, matching the old `<h1>`'s "Nuevo campo — X" / "Editar campo — X" text):

```erb
<%= admin_card("#{field_definition.persisted? ? 'Editar' : 'Nuevo'} campo — #{project_type.name}") do %>
  <%= form_with model: [:admin, project_type, field_definition] do |form| %>
    <% if field_definition.errors.any? %>
      <div class="alert alert-danger">
        <ul class="mb-0">
          <% field_definition.errors.full_messages.each do |message| %>
            <li><%= message %></li>
          <% end %>
        </ul>
      </div>
    <% end %>

    <div class="mb-3">
      <%= form.label :key, class: "form-label" %>
      <%= form.text_field :key, class: "form-control" %>
    </div>
    <div class="mb-3">
      <%= form.label :label, class: "form-label" %>
      <%= form.text_field :label, class: "form-control" %>
    </div>
    <div class="mb-3">
      <%= form.label :data_type, class: "form-label" %>
      <%= form.select :data_type, FieldDefinition::DATA_TYPES.map { |dt| [FieldDefinition::DATA_TYPE_LABELS[dt], dt] }, {}, class: "form-select" %>
    </div>
    <div class="mb-3">
      <%= form.label :reference_table, class: "form-label" %>
      <%= form.text_field :reference_table, class: "form-control" %>
    </div>
    <div class="mb-3">
      <%= form.label :position, class: "form-label" %>
      <%= form.number_field :position, class: "form-control" %>
    </div>
    <div class="form-check mb-3">
      <%= form.check_box :show_in_gantt, class: "form-check-input" %>
      <%= form.label :show_in_gantt, class: "form-check-label" %>
    </div>
    <%= form.submit class: "btn btn-primary" %>
  <% end %>
<% end %>
```

Replace `new.html.erb` with:
```erb
<%= render "form", project_type: @project_type, field_definition: @field_definition %>
```

Replace `edit.html.erb` with:
```erb
<%= render "form", project_type: @project_type, field_definition: @field_definition %>
```

- [ ] **Step 5: `stage_templates/_form.html.erb`, `new.html.erb`, `edit.html.erb`**

Read all three current files first. Replace `_form.html.erb`'s contents:

```erb
<%= admin_card("#{stage_template.persisted? ? 'Editar' : 'Nuevo'} subproceso — #{project_type.name}") do %>
  <%= form_with model: [:admin, project_type, stage_template] do |form| %>
    <% if stage_template.errors.any? %>
      <div class="alert alert-danger">
        <ul class="mb-0">
          <% stage_template.errors.full_messages.each do |message| %>
            <li><%= message %></li>
          <% end %>
        </ul>
      </div>
    <% end %>

    <div class="mb-3">
      <%= form.label :name, class: "form-label" %>
      <%= form.text_field :name, class: "form-control" %>
    </div>
    <div class="mb-3">
      <%= form.label :position, class: "form-label" %>
      <%= form.number_field :position, class: "form-control" %>
    </div>
    <div class="mb-3">
      <%= form.label :color, class: "form-label" %>
      <%= form.color_field :color, class: "form-control form-control-color" %>
    </div>
    <div class="mb-3 form-check">
      <%= form.check_box :default_in_filter, class: "form-check-input" %>
      <%= form.label :default_in_filter, "Etapa por defecto en el filtro", class: "form-check-label" %>
    </div>
    <%= form.submit class: "btn btn-primary" %>
  <% end %>
<% end %>
```

Replace `new.html.erb` with:
```erb
<%= render "form", project_type: @project_type, stage_template: @stage_template %>
```

Replace `edit.html.erb` with:
```erb
<%= render "form", project_type: @project_type, stage_template: @stage_template %>
```

- [ ] **Step 6: Run the three test files to verify they still pass**

```bash
bin/rails test test/controllers/admin/project_types_controller_test.rb test/controllers/admin/field_definitions_controller_test.rb test/controllers/admin/stage_templates_controller_test.rb
```
Expected: PASS — these tests assert on submit-button values (`"Crear Subproceso"` etc.) and specific input names/checkboxes, none of which changed; only the wrapping markup changed.

- [ ] **Step 7: Run the full suite**

```bash
bin/rails test
```
Expected: PASS, 0 failures, 0 errors.

- [ ] **Step 8: Commit**

```bash
git add app/views/admin/project_types app/views/admin/field_definitions app/views/admin/stage_templates
git commit -m "Wrap project_types/field_definitions/stage_templates admin views in cards"
```

---

### Task 3: `log_entry_types`, `installers` views

**Files:**
- Modify: `app/views/admin/log_entry_types/new.html.erb`
- Modify: `app/views/admin/log_entry_types/edit.html.erb`
- Modify: `app/views/admin/log_entry_types/_form.html.erb`
- Modify: `app/views/admin/installers/index.html.erb`
- Modify: `app/views/admin/installers/new.html.erb`
- Modify: `app/views/admin/installers/edit.html.erb`
- Modify: `app/views/admin/installers/_form.html.erb`
- Test: `test/controllers/admin/log_entry_types_controller_test.rb`, `test/controllers/admin/installers_controller_test.rb`

**Interfaces:**
- Consumes: `admin_card` (Task 1).

- [ ] **Step 1: Run the two existing test files to record the baseline**

```bash
bin/rails test test/controllers/admin/log_entry_types_controller_test.rb test/controllers/admin/installers_controller_test.rb
```
Expected: PASS (baseline).

- [ ] **Step 2: `log_entry_types/_form.html.erb`, `new.html.erb`, `edit.html.erb`**

Read all three current files first. Replace `_form.html.erb`'s contents (this one is unusual — it doesn't take local variables, it reads `@project_type`/`@log_entry_type` directly, per the existing file; keep that as-is, just wrap it):

```erb
<%= admin_card(@log_entry_type.persisted? ? "Editar Tipo de Bitácora" : "Nuevo Tipo de Bitácora") do %>
  <%= form_with model: [@project_type, @log_entry_type], url: @log_entry_type.persisted? ? admin_project_type_log_entry_type_path(@project_type, @log_entry_type) : admin_project_type_log_entry_types_path(@project_type) do |f| %>
    <div class="mb-3">
      <%= f.label :name, "Nombre" %>
      <%= f.text_field :name, class: "form-control" %>
    </div>
    <div class="mb-3">
      <%= f.label :color, "Color" %>
      <%= f.color_field :color, class: "form-control form-control-color" %>
    </div>
    <%= f.submit (@log_entry_type.persisted? ? "Actualizar Tipo de Bitácora" : "Crear Tipo de Bitácora"), class: "btn btn-primary" %>
  <% end %>
<% end %>
```

Replace `new.html.erb` with:
```erb
<%= render "form" %>
```

Replace `edit.html.erb` with:
```erb
<%= render "form" %>
```

- [ ] **Step 3: `installers/index.html.erb`**

Read the current file first (bare `<h1>Instaladores</h1>` + button + `<ul class="list-group">`). Replace with:

```erb
<%= admin_card("Instaladores") do %>
  <%= link_to "Nuevo instalador", new_admin_installer_path, class: "btn btn-primary mb-3" %>
  <ul class="list-group">
    <% @installers.each do |installer| %>
      <li class="list-group-item d-flex justify-content-between align-items-center">
        <%= installer.name %>
        <span>
          <%= link_to "Editar", edit_admin_installer_path(installer), class: "btn btn-outline-secondary btn-sm" %>
          <%= button_to "Borrar", admin_installer_path(installer), method: :delete,
                class: "btn btn-outline-danger btn-sm", form: { style: "display:inline-block", onsubmit: "return confirm('¿Eliminar instalador?')" } %>
        </span>
      </li>
    <% end %>
  </ul>
<% end %>
```

- [ ] **Step 4: `installers/_form.html.erb`, `new.html.erb`, `edit.html.erb`**

Read all three current files first. Replace `_form.html.erb`'s contents:

```erb
<%= admin_card(installer.persisted? ? "Editar instalador" : "Nuevo instalador") do %>
  <%= form_with model: [:admin, installer] do |form| %>
    <% if installer.errors.any? %>
      <div class="alert alert-danger">
        <ul class="mb-0">
          <% installer.errors.full_messages.each do |message| %>
            <li><%= message %></li>
          <% end %>
        </ul>
      </div>
    <% end %>

    <div class="mb-3">
      <%= form.label :name, class: "form-label" %>
      <%= form.text_field :name, class: "form-control" %>
    </div>

    <div class="mb-3">
      <%= form.label :color, class: "form-label" %>
      <%= form.color_field :color, class: "form-control form-control-color" %>
    </div>
    <%= form.submit class: "btn btn-primary" %>
  <% end %>
<% end %>
```

Replace `new.html.erb` with:
```erb
<%= render "form", installer: @installer %>
```

Replace `edit.html.erb` with:
```erb
<%= render "form", installer: @installer %>
```

- [ ] **Step 5: Run the two test files to verify they still pass**

```bash
bin/rails test test/controllers/admin/log_entry_types_controller_test.rb test/controllers/admin/installers_controller_test.rb
```
Expected: PASS — including `"index asks for confirmation before deleting an installer"` and `"new and edit show the submit button in Spanish"`, both unaffected by the wrapping change.

- [ ] **Step 6: Run the full suite**

```bash
bin/rails test
```
Expected: PASS, 0 failures, 0 errors.

- [ ] **Step 7: Commit**

```bash
git add app/views/admin/log_entry_types app/views/admin/installers
git commit -m "Wrap log_entry_types/installers admin views in cards"
```

---

### Task 4: `admin/users` views + role badges

**Files:**
- Modify: `app/views/admin/users/index.html.erb`
- Modify: `app/views/admin/users/new.html.erb`
- Modify: `app/views/admin/users/edit.html.erb`
- Modify: `app/views/admin/users/_form.html.erb`
- Modify: `app/helpers/application_helper.rb`
- Test: `test/controllers/admin/users_controller_test.rb`

**Interfaces:**
- Consumes: `admin_card` (Task 1).

- [ ] **Step 1: Run the existing test file to record the baseline**

```bash
bin/rails test test/controllers/admin/users_controller_test.rb
```
Expected: PASS (baseline — this file has ~12 tests as of the roles feature, including the access-grant marker tests).

- [ ] **Step 2: Add the role badge helper**

Read `app/helpers/application_helper.rb` first (it now has `admin_card` from Task 1). Add `ROLE_BADGE_CLASSES` alongside the existing `ROLE_LABELS` constant, and `role_badge_class` alongside `role_label`:

```ruby
  ROLE_BADGE_CLASSES = { "admin" => "bg-primary", "gerente" => "bg-info text-dark", "visor" => "bg-secondary" }.freeze
```
(add this line right after `ROLE_LABELS = ...`)

```ruby
  def role_badge_class(role)
    ROLE_BADGE_CLASSES.fetch(role, "bg-light text-dark")
  end
```
(add this method right after `role_label`)

- [ ] **Step 3: `admin/users/index.html.erb`**

Read the current file first. Replace with:

```erb
<%= admin_card("Usuarios") do %>
  <%= link_to "Nuevo usuario", new_admin_user_path, class: "btn btn-primary mb-3" %>
  <table class="table align-middle">
    <thead>
      <tr><th>Correo electrónico</th><th>Rol</th><th></th></tr>
    </thead>
    <tbody>
      <% @users.each do |user| %>
        <tr>
          <td><%= user.email %></td>
          <td><span class="badge <%= role_badge_class(user.role) %>"><%= role_label(user.role) %></span></td>
          <td>
            <%= link_to "Editar", edit_admin_user_path(user), class: "btn btn-outline-secondary btn-sm" %>
            <%= button_to "Eliminar", admin_user_path(user), method: :delete,
                  class: "btn btn-outline-danger btn-sm", form: { style: "display:inline-block", onsubmit: "return confirm('¿Eliminar usuario?')" } %>
          </td>
        </tr>
      <% end %>
    </tbody>
  </table>
<% end %>
```

- [ ] **Step 4: `admin/users/_form.html.erb`**

Read the current file in full first (it has: a `form_with` for email/role/password, then, if `user.persisted?`, an `<hr>` + `<h2>Accesos a proyectos</h2>` + a per-project-type table of checkboxes + a second `form_with` with the `sync_project_access` hidden marker). Restructure into two `admin_card`s — the details form and, only when persisted, the access-grants section — keeping every field, name, id, and the `sync_project_access` marker mechanism byte-for-byte identical, just re-wrapped:

```erb
<%= admin_card(user.persisted? ? "Editar usuario" : "Nuevo usuario") do %>
  <%= form_with model: [:admin, user] do |form| %>
    <% if user.errors.any? %>
      <div class="alert alert-danger">
        <ul class="mb-0">
          <% user.errors.full_messages.each do |message| %>
            <li><%= message %></li>
          <% end %>
        </ul>
      </div>
    <% end %>

    <div class="mb-3">
      <%= form.label :email, "Correo electrónico", class: "form-label" %>
      <%= form.email_field :email, class: "form-control" %>
    </div>

    <div class="mb-3">
      <%= form.label :role, "Rol", class: "form-label" %>
      <%= form.select :role, User.roles.keys.map { |r| [role_label(r), r] }, {}, class: "form-select" %>
    </div>

    <div class="mb-3">
      <%= form.label :password, "Contraseña", class: "form-label" %>
      <% if user.persisted? %><div class="form-text">Dejalo en blanco si no querés cambiarla.</div><% end %>
      <%= form.password_field :password, class: "form-control", autocomplete: "new-password" %>
    </div>

    <div class="mb-3">
      <%= form.label :password_confirmation, "Confirmación de contraseña", class: "form-label" %>
      <%= form.password_field :password_confirmation, class: "form-control", autocomplete: "new-password" %>
    </div>

    <%= form.submit (user.persisted? ? "Actualizar Usuario" : "Crear Usuario"), class: "btn btn-primary" %>
  <% end %>
<% end %>

<% if user.persisted? %>
  <%= admin_card("Accesos a proyectos") do %>
    <p class="text-muted">
      "Ver" alcanza para un rol Visor. "Editar" solo tiene efecto para un rol Gerente
      (Admin siempre tiene acceso total; Gerente siempre puede ver todos los proyectos).
    </p>
    <% @projects.group_by(&:project_type).each do |project_type, projects| %>
      <h3 class="h6"><%= project_type.name %></h3>
      <table class="table table-sm">
        <thead><tr><th>Proyecto</th><th>Ver</th><th>Editar</th></tr></thead>
        <tbody>
          <% projects.each do |project| %>
            <% access = user.project_accesses.find { |a| a.project_id == project.id } %>
            <tr>
              <td><%= project.name %></td>
              <td><%= check_box_tag "project_access[#{project.id}][view]", "1", access.present?, form: "user-access-form" %></td>
              <td><%= check_box_tag "project_access[#{project.id}][edit]", "1", access&.can_edit || false, form: "user-access-form" %></td>
            </tr>
          <% end %>
        </tbody>
      </table>
    <% end %>
    <%= form_with url: admin_user_path(user), method: :patch, id: "user-access-form" do %>
      <%= hidden_field_tag "user[email]", user.email %>
      <%= hidden_field_tag "user[role]", user.role %>
      <%= hidden_field_tag "sync_project_access", "1" %>
      <%= submit_tag "Guardar accesos", class: "btn btn-primary" %>
    <% end %>
  <% end %>
<% end %>
```

- [ ] **Step 5: `admin/users/new.html.erb`, `edit.html.erb`**

Read both current files first (each is `<h1>...</h1>` + `render "form"`). Replace both with just:
```erb
<%= render "form", user: @user %>
```
(identical content for `new.html.erb` and `edit.html.erb` — the `_form` partial's own `admin_card` call handles the persisted?/new distinction now.)

- [ ] **Step 6: Run the users controller test to verify it still passes**

```bash
bin/rails test test/controllers/admin/users_controller_test.rb
```
Expected: PASS (all tests, including the `sync_project_access` marker tests and the FK-rescue-on-destroy test from the roles feature — none of that behavior changed, only the surrounding markup).

- [ ] **Step 7: Run the full suite**

```bash
bin/rails test
```
Expected: PASS, 0 failures, 0 errors — this is the last task.

- [ ] **Step 8: Commit**

```bash
git add app/views/admin/users app/helpers/application_helper.rb
git commit -m "Wrap admin/users views in cards, add role badges"
```

---

## Post-Plan Manual Verification

- [ ] Load `/users/sign_in` signed out — confirm the centered card renders with the person icon, and the form is usable.
- [ ] Load each of: `/admin/project_types`, `/admin/project_types/new`, `/admin/installers`, `/admin/installers/new`, `/admin/users`, `/admin/users/new` — confirm each shows a card with a header matching the old page title.
- [ ] Load `/admin/project_types/:id` (the untouched `show.html.erb`) — confirm its 3 existing cards now show the subtle shadow from the new global CSS, and drag-and-drop reordering still works.
- [ ] Load `/admin/users/:id` for an existing user — confirm the "Datos del usuario" and "Accesos a proyectos" cards both render, checkboxes reflect existing grants, and saving each form independently still works (submitting email/role alone doesn't wipe access grants; submitting access grants alone doesn't touch email/role).
