# Devise recoverable/confirmable + modern mailer emails Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add "olvidé mi contraseña" and "confirmación de cuenta por email" to Devise, with password-change/email-change notification emails, all rendered through a modern, branded HTML mailer layout.

**Architecture:** Enable Devise's `:recoverable` and `:confirmable` modules on `User` (migration + model line), wire up the web-facing Devise views (passwords, confirmations) in the app's existing Bootstrap style, and replace the default plain-text Devise mailer views with a single reusable branded HTML layout + per-action content views. SMTP delivery and `Devise::Mailer`'s `parent_mailer` are already configured from prior work.

**Tech Stack:** Rails 7.2, Devise 5.0.4, Minitest (fixtures, `ActionMailer::TestCase`, `ActionDispatch::IntegrationTest`), Bootstrap 5 (already loaded via CDN in the layout).

## Global Constraints

- Brand color for all email CTAs/accents: `#2563EB` (app/assets/stylesheets/application.css:18).
- All email CSS must be inline — no `<style>` block reliance (Gmail/Outlook strip or ignore head styles).
- No logo image in emails — text wordmark "Nalakalu" only, to avoid broken-image-in-email issues.
- Every mailer content view needs both `.html.erb` and `.text.erb`.
- `I18n.default_locale` is `:es` (config/application.rb:27); all user-facing copy is Spanish. Devise flash/subject translations already exist in `config/locales/devise.es.yml` — do not add new locale keys, only body copy in the view files themselves.
- The admin user-creation flow (`Admin::UsersController`, `app/views/admin/users/_form.html.erb`) does not change — the admin still sets the initial password.
- `:registerable` stays skipped (config/routes.rb:2) — no self-signup.
- Existing fixtures: `test/fixtures/users.yml` has `juan` (admin), `carla` (gerente), `maria` (visor), `pedro` (responsable), all with `encrypted_password` via `Devise::Encryptor.digest`.

---

### Task 1: Enable `:recoverable` and `:confirmable` on `User`

**Files:**
- Create: `db/migrate/20260810100000_add_confirmable_to_users.rb`
- Modify: `app/models/user.rb:4`
- Modify: `test/fixtures/users.yml`
- Test: `test/models/user_test.rb`

**Interfaces:**
- Produces: `User#confirmed?`, `User#send_confirmation_instructions`, `User#send_reset_password_instructions` (from Devise modules) — used by Task 8/9's integration tests and any future Devise-driven auth flow.

- [ ] **Step 1: Write the failing test**

Add to `test/models/user_test.rb` (after the existing `test "role accepts admin, gerente, and visor"` block):

```ruby
  test "supports devise recoverable and confirmable" do
    user = users(:juan)
    assert_respond_to user, :confirmed?
    assert_respond_to user, :send_reset_password_instructions
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/models/user_test.rb -n "/supports devise recoverable and confirmable/"`
Expected: FAIL — `NoMethodError` or `assert_respond_to` failure, because `User` doesn't have `:recoverable`/`:confirmable` yet.

- [ ] **Step 3: Write the migration**

```ruby
# db/migrate/20260810100000_add_confirmable_to_users.rb
class AddConfirmableToUsers < ActiveRecord::Migration[7.2]
  def up
    add_column :users, :confirmation_token, :string
    add_column :users, :confirmed_at, :datetime
    add_column :users, :confirmation_sent_at, :datetime
    add_column :users, :unconfirmed_email, :string
    add_index :users, :confirmation_token, unique: true

    # Backfill: existing users are already-trusted accounts, don't lock
    # them out of login behind a confirmation email they never asked for.
    execute "UPDATE users SET confirmed_at = created_at WHERE confirmed_at IS NULL"
  end

  def down
    remove_index :users, :confirmation_token
    remove_column :users, :unconfirmed_email
    remove_column :users, :confirmation_sent_at
    remove_column :users, :confirmed_at
    remove_column :users, :confirmation_token
  end
end
```

- [ ] **Step 4: Run the migration**

Run: `bin/rails db:migrate`
Expected: migration applies; `db/schema.rb` now shows `confirmation_token`, `confirmed_at`, `confirmation_sent_at`, `unconfirmed_email` on `users`, and the schema `version:` at the top bumps to `2026_08_10_100000`.

- [ ] **Step 5: Update the model**

In `app/models/user.rb:4`, change:

```ruby
  devise :database_authenticatable, :rememberable, :validatable
```

to:

```ruby
  devise :database_authenticatable, :rememberable, :validatable, :recoverable, :confirmable
```

- [ ] **Step 6: Run test to verify it passes**

Run: `bin/rails test test/models/user_test.rb -n "/supports devise recoverable and confirmable/"`
Expected: PASS

- [ ] **Step 7: Confirm existing tests and fixtures still work**

Existing fixtures have no `confirmed_at`, meaning any test that logs in through the *real* Warden authentication path (not the `sign_in` test helper) would now fail. Update `test/fixtures/users.yml` to add `confirmed_at: <%= Time.current %>` to all four fixtures:

```yaml
juan:
  email: juan@example.com
  encrypted_password: <%= Devise::Encryptor.digest(User, "password123") %>
  role: admin
  confirmed_at: <%= Time.current %>

carla:
  email: carla@example.com
  encrypted_password: <%= Devise::Encryptor.digest(User, "password123") %>
  role: gerente
  confirmed_at: <%= Time.current %>

maria:
  email: maria@example.com
  encrypted_password: <%= Devise::Encryptor.digest(User, "password123") %>
  role: visor
  confirmed_at: <%= Time.current %>

pedro:
  email: pedro@example.com
  encrypted_password: <%= Devise::Encryptor.digest(User, "password123") %>
  role: responsable
  confirmed_at: <%= Time.current %>
```

Run: `bin/rails db:test:prepare` (loads the new schema into the test DB), then `bin/rails test`
Expected: full suite passes (0 failures, 0 errors) — confirms the migration/backfill/fixtures didn't regress anything.

- [ ] **Step 8: Commit**

```bash
git add db/migrate/20260810100000_add_confirmable_to_users.rb db/schema.rb app/models/user.rb test/fixtures/users.yml test/models/user_test.rb
git commit -m "Habilitar Devise recoverable y confirmable en User"
```

---

### Task 2: Notification config for password/email changes

**Files:**
- Modify: `config/initializers/devise.rb:131-135`

**Interfaces:**
- Consumes: nothing new.
- Produces: enables Devise's built-in `Devise::Mailer#password_change` / `#email_changed` callbacks, which Task 4's mailer views render.

- [ ] **Step 1: Enable the two notification flags**

In `config/initializers/devise.rb`, change:

```ruby
  # Send a notification to the original email when the user's email is changed.
  # config.send_email_changed_notification = false

  # Send a notification email when the user's password is changed.
  # config.send_password_change_notification = false
```

to:

```ruby
  # Send a notification to the original email when the user's email is changed.
  config.send_email_changed_notification = true

  # Send a notification email when the user's password is changed.
  config.send_password_change_notification = true
```

- [ ] **Step 2: Verify the app boots with the new config**

Run: `bin/rails runner "puts Devise.send_password_change_notification"`
Expected: prints `true`

- [ ] **Step 3: Commit**

```bash
git add config/initializers/devise.rb
git commit -m "Habilitar notificaciones de cambio de contraseña y de email en Devise"
```

---

### Task 3: Modern branded mailer layout

**Files:**
- Modify: `app/views/layouts/mailer.html.erb`
- Create: `app/views/devise/mailer/_button.html.erb`
- Test: `test/mailers/devise_mailer_test.rb`

**Interfaces:**
- Produces: `render "devise/mailer/button", url:, label:` — a locals-based partial any mailer content view can render for a CTA button. `app/views/layouts/mailer.html.erb` wraps every mailer's `.html.erb` view (declared via `layout "mailer"` in `app/mailers/application_mailer.rb:3`, inherited by `Devise::Mailer` through `parent_mailer`).

- [ ] **Step 1: Write the failing test**

Create `test/mailers/devise_mailer_test.rb`:

```ruby
require "test_helper"

class DeviseMailerTest < ActionMailer::TestCase
  setup { @user = users(:juan) }

  test "confirmation_instructions renders the branded layout" do
    mail = Devise::Mailer.confirmation_instructions(@user, "faketoken")
    assert_match "Nalakalu", mail.html_part.body.to_s
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/mailers/devise_mailer_test.rb`
Expected: FAIL — `devise/mailer/confirmation_instructions` template missing (that view doesn't exist yet; this task only lays the layout/partial groundwork, so this test stays red until Task 4). Confirm the failure is specifically a missing-template error, not a layout error.

- [ ] **Step 3: Rewrite the mailer layout**

Replace `app/views/layouts/mailer.html.erb`:

```erb
<!DOCTYPE html>
<html lang="es">
  <head>
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
  </head>
  <body style="margin:0; padding:0; background-color:#F1F5F9; font-family:-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background-color:#F1F5F9;">
      <tr>
        <td align="center" style="padding:32px 16px;">
          <table role="presentation" width="480" cellpadding="0" cellspacing="0" style="max-width:480px; width:100%;">
            <tr>
              <td style="padding:0 8px 24px; text-align:center;">
                <span style="font-size:20px; font-weight:700; color:#2563EB; letter-spacing:0.5px;">Nalakalu</span>
              </td>
            </tr>
            <tr>
              <td style="background-color:#FFFFFF; border-radius:8px; padding:32px; box-shadow:0 1px 3px rgba(0,0,0,0.08);">
                <%= yield %>
              </td>
            </tr>
            <tr>
              <td style="padding:24px 8px 0; text-align:center; font-size:12px; color:#94A3B8;">
                Si no solicitaste esto, podés ignorar este correo.
              </td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
  </body>
</html>
```

- [ ] **Step 4: Create the CTA button partial**

Create `app/views/devise/mailer/_button.html.erb`:

```erb
<table role="presentation" cellpadding="0" cellspacing="0" style="margin:24px 0;">
  <tr>
    <td style="border-radius:6px; background-color:#2563EB;">
      <a href="<%= url %>" style="display:inline-block; padding:12px 24px; font-size:14px; font-weight:600; color:#FFFFFF; text-decoration:none; border-radius:6px;">
        <%= label %>
      </a>
    </td>
  </tr>
</table>
```

- [ ] **Step 5: Run test to verify it still fails the same way**

Run: `bin/rails test test/mailers/devise_mailer_test.rb`
Expected: still FAIL with a missing-template error for `devise/mailer/confirmation_instructions` (layout and partial exist now, but no content view calls them yet — that's Task 4). This confirms the layout itself isn't the blocker.

- [ ] **Step 6: Commit**

```bash
git add app/views/layouts/mailer.html.erb app/views/devise/mailer/_button.html.erb test/mailers/devise_mailer_test.rb
git commit -m "Agregar layout de mailer moderno y partial de botón CTA"
```

---

### Task 4: Confirmation and reset-password email content

**Files:**
- Create: `app/views/devise/mailer/confirmation_instructions.html.erb`
- Create: `app/views/devise/mailer/confirmation_instructions.text.erb`
- Create: `app/views/devise/mailer/reset_password_instructions.html.erb`
- Create: `app/views/devise/mailer/reset_password_instructions.text.erb`
- Modify: `test/mailers/devise_mailer_test.rb`

**Interfaces:**
- Consumes: `app/views/devise/mailer/_button.html.erb` (Task 3), `@resource`/`@token` set by `Devise::Mailer` (gem code, not app code).

- [ ] **Step 1: Write the failing tests**

Add to `test/mailers/devise_mailer_test.rb`:

```ruby
  test "confirmation_instructions has the confirmation link and CTA label" do
    mail = Devise::Mailer.confirmation_instructions(@user, "faketoken")
    assert_equal "Instrucciones de confirmación", mail.subject
    assert_equal [@user.email], mail.to
    body = mail.html_part.body.to_s
    assert_match "Confirmar mi cuenta", body
    assert_match "confirmation_token=faketoken", body
    assert_match "faketoken", mail.text_part.body.to_s
  end

  test "reset_password_instructions has the reset link and CTA label" do
    mail = Devise::Mailer.reset_password_instructions(@user, "faketoken")
    assert_equal "Instrucciones para restablecer tu contraseña", mail.subject
    body = mail.html_part.body.to_s
    assert_match "Cambiar mi contraseña", body
    assert_match "reset_password_token=faketoken", body
    assert_match "faketoken", mail.text_part.body.to_s
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/mailers/devise_mailer_test.rb`
Expected: FAIL — missing templates for both actions.

- [ ] **Step 3: Write the confirmation view**

Create `app/views/devise/mailer/confirmation_instructions.html.erb`:

```erb
<h1 style="margin:0 0 16px; font-size:20px; color:#0F172A;">Confirmá tu cuenta</h1>
<p style="margin:0 0 16px; font-size:15px; line-height:1.5; color:#334155;">Hola <%= @resource.email %>,</p>
<p style="margin:0 0 16px; font-size:15px; line-height:1.5; color:#334155;">
  Creamos una cuenta para vos en Nalakalu Proyectos. Confirmá tu correo electrónico para poder iniciar sesión.
</p>
<%= render "devise/mailer/button", url: confirmation_url(@resource, confirmation_token: @token), label: "Confirmar mi cuenta" %>
<p style="margin:16px 0 0; font-size:13px; line-height:1.5; color:#64748B;">
  Si no esperabas este correo, podés ignorarlo.
</p>
```

Create `app/views/devise/mailer/confirmation_instructions.text.erb`:

```erb
Hola <%= @resource.email %>,

Creamos una cuenta para vos en Nalakalu Proyectos. Confirmá tu correo electrónico entrando al siguiente link:

<%= confirmation_url(@resource, confirmation_token: @token) %>

Si no esperabas este correo, podés ignorarlo.
```

- [ ] **Step 4: Write the reset-password view**

Create `app/views/devise/mailer/reset_password_instructions.html.erb`:

```erb
<h1 style="margin:0 0 16px; font-size:20px; color:#0F172A;">Restablecé tu contraseña</h1>
<p style="margin:0 0 16px; font-size:15px; line-height:1.5; color:#334155;">Hola <%= @resource.email %>,</p>
<p style="margin:0 0 16px; font-size:15px; line-height:1.5; color:#334155;">
  Alguien pidió cambiar la contraseña de esta cuenta. Si fuiste vos, hacé clic abajo para elegir una nueva.
</p>
<%= render "devise/mailer/button", url: edit_password_url(@resource, reset_password_token: @token), label: "Cambiar mi contraseña" %>
<p style="margin:16px 0 0; font-size:13px; line-height:1.5; color:#64748B;">
  Este enlace expira en <%= (Devise.reset_password_within / 1.hour).to_i %> horas. Si no lo solicitaste, podés ignorar este correo — tu contraseña no va a cambiar.
</p>
```

Create `app/views/devise/mailer/reset_password_instructions.text.erb`:

```erb
Hola <%= @resource.email %>,

Alguien pidió cambiar la contraseña de esta cuenta. Si fuiste vos, entrá al siguiente link para elegir una nueva:

<%= edit_password_url(@resource, reset_password_token: @token) %>

Este enlace expira en <%= (Devise.reset_password_within / 1.hour).to_i %> horas. Si no lo solicitaste, podés ignorar este correo — tu contraseña no va a cambiar.
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bin/rails test test/mailers/devise_mailer_test.rb`
Expected: PASS (all 3 tests so far)

- [ ] **Step 6: Commit**

```bash
git add app/views/devise/mailer/confirmation_instructions.html.erb app/views/devise/mailer/confirmation_instructions.text.erb app/views/devise/mailer/reset_password_instructions.html.erb app/views/devise/mailer/reset_password_instructions.text.erb test/mailers/devise_mailer_test.rb
git commit -m "Agregar vistas de email para confirmación y reset de contraseña"
```

---

### Task 5: Password-change and email-changed notification emails

**Files:**
- Create: `app/views/devise/mailer/password_change.html.erb`
- Create: `app/views/devise/mailer/password_change.text.erb`
- Create: `app/views/devise/mailer/email_changed.html.erb`
- Create: `app/views/devise/mailer/email_changed.text.erb`
- Modify: `test/mailers/devise_mailer_test.rb`

**Interfaces:**
- Consumes: `@resource` set by `Devise::Mailer` (gem code).

- [ ] **Step 1: Write the failing tests**

Add to `test/mailers/devise_mailer_test.rb`:

```ruby
  test "password_change notifies with no CTA link" do
    mail = Devise::Mailer.password_change(@user)
    assert_equal "Contraseña modificada", mail.subject
    body = mail.html_part.body.to_s
    assert_match @user.email, body
    assert_no_match "href=", body
  end

  test "email_changed notifies about a pending reconfirmation" do
    # reconfirmable's postpone-and-set-unconfirmed_email logic is a before_save
    # callback, so it only runs on save/update, not on a bare assignment.
    @user.update!(email: "nuevo@example.com")
    mail = Devise::Mailer.email_changed(@user)
    assert_equal "Correo electrónico modificado", mail.subject
    body = mail.html_part.body.to_s
    assert_match "nuevo@example.com", body
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/mailers/devise_mailer_test.rb`
Expected: FAIL — missing templates for both actions.

- [ ] **Step 3: Write the password-change view**

Create `app/views/devise/mailer/password_change.html.erb`:

```erb
<h1 style="margin:0 0 16px; font-size:20px; color:#0F172A;">Tu contraseña cambió</h1>
<p style="margin:0 0 16px; font-size:15px; line-height:1.5; color:#334155;">Hola <%= @resource.email %>,</p>
<p style="margin:0; font-size:15px; line-height:1.5; color:#334155;">
  Te avisamos que la contraseña de tu cuenta se cambió el <%= I18n.l(Time.current, format: :short) %>. Si no fuiste vos, contactá al administrador de inmediato.
</p>
```

Create `app/views/devise/mailer/password_change.text.erb`:

```erb
Hola <%= @resource.email %>,

Te avisamos que la contraseña de tu cuenta se cambió el <%= I18n.l(Time.current, format: :short) %>. Si no fuiste vos, contactá al administrador de inmediato.
```

- [ ] **Step 4: Write the email-changed view**

Create `app/views/devise/mailer/email_changed.html.erb`:

```erb
<h1 style="margin:0 0 16px; font-size:20px; color:#0F172A;">Se solicitó un cambio de correo electrónico</h1>
<p style="margin:0 0 16px; font-size:15px; line-height:1.5; color:#334155;">Hola,</p>
<% if @resource.try(:unconfirmed_email?) %>
  <p style="margin:0; font-size:15px; line-height:1.5; color:#334155;">
    Te avisamos que se pidió cambiar el correo electrónico de tu cuenta a <strong><%= @resource.unconfirmed_email %></strong>. El cambio no se aplica hasta confirmar el nuevo correo. Si no fuiste vos, contactá al administrador de inmediato.
  </p>
<% else %>
  <p style="margin:0; font-size:15px; line-height:1.5; color:#334155;">
    Te avisamos que el correo electrónico de tu cuenta cambió a <strong><%= @resource.email %></strong>. Si no fuiste vos, contactá al administrador de inmediato.
  </p>
<% end %>
```

Create `app/views/devise/mailer/email_changed.text.erb`:

```erb
Hola,

<% if @resource.try(:unconfirmed_email?) %>
Te avisamos que se pidió cambiar el correo electrónico de tu cuenta a <%= @resource.unconfirmed_email %>. El cambio no se aplica hasta confirmar el nuevo correo. Si no fuiste vos, contactá al administrador de inmediato.
<% else %>
Te avisamos que el correo electrónico de tu cuenta cambió a <%= @resource.email %>. Si no fuiste vos, contactá al administrador de inmediato.
<% end %>
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bin/rails test test/mailers/devise_mailer_test.rb`
Expected: PASS (all 5 tests)

- [ ] **Step 6: Commit**

```bash
git add app/views/devise/mailer/password_change.html.erb app/views/devise/mailer/password_change.text.erb app/views/devise/mailer/email_changed.html.erb app/views/devise/mailer/email_changed.text.erb test/mailers/devise_mailer_test.rb
git commit -m "Agregar vistas de email para cambio de contraseña y de correo"
```

---

### Task 6: "Olvidé mi contraseña" web form (recoverable)

**Files:**
- Create: `app/views/devise/passwords/new.html.erb`
- Create: `app/views/devise/passwords/edit.html.erb`
- Test: `test/controllers/passwords_flow_test.rb`

**Interfaces:**
- Consumes: Devise route helpers `password_path`, `edit_password_url` (already available app-wide via `devise_for :users`).

- [ ] **Step 1: Write the failing test**

Create `test/controllers/passwords_flow_test.rb`:

```ruby
require "test_helper"

class PasswordsFlowTest < ActionDispatch::IntegrationTest
  test "user resets their password end to end" do
    user = users(:juan)

    get new_user_password_path
    assert_response :success
    assert_select "h2", "Recuperar contraseña"

    assert_emails 1 do
      post user_password_path, params: { user: { email: user.email } }
    end

    mail = ActionMailer::Base.deliveries.last
    token = mail.html_part.body.to_s[/reset_password_token=([^"&]+)/, 1]
    assert token.present?

    get edit_user_password_path(reset_password_token: token)
    assert_response :success

    put user_password_path, params: {
      user: { reset_password_token: token, password: "newpassword123", password_confirmation: "newpassword123" }
    }
    assert_redirected_to root_path

    delete destroy_user_session_path

    post user_session_path, params: { user: { email: user.email, password: "newpassword123" } }
    assert_redirected_to root_path
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/passwords_flow_test.rb`
Expected: FAIL — `ActionView::MissingTemplate` for `devise/passwords/new` (the view doesn't exist yet).

- [ ] **Step 3: Write the "forgot password" form**

Create `app/views/devise/passwords/new.html.erb`:

```erb
<div class="row justify-content-center">
  <div class="col-md-5 col-lg-4">
    <div class="card shadow-sm mt-5">
      <div class="card-body p-4">
        <div class="text-center mb-4">
          <i class="bi bi-key" style="font-size: 2.5rem; color: var(--bs-primary);"></i>
          <h2 class="h4 mt-2 mb-0">Recuperar contraseña</h2>
        </div>

        <%= form_for(resource, as: resource_name, url: password_path(resource_name), html: { method: :post }) do |f| %>
          <%= render "devise/shared/error_messages", resource: resource %>

          <div class="mb-3">
            <%= f.label :email, "Correo electrónico", class: "form-label" %>
            <%= f.email_field :email, autofocus: true, autocomplete: "email", class: "form-control" %>
          </div>

          <%= f.submit "Enviar instrucciones", class: "btn btn-primary w-100" %>
        <% end %>

        <div class="text-center mt-3 small">
          <%= render "devise/shared/links" %>
        </div>
      </div>
    </div>
  </div>
</div>
```

- [ ] **Step 4: Write the "set new password" form**

Create `app/views/devise/passwords/edit.html.erb`:

```erb
<div class="row justify-content-center">
  <div class="col-md-5 col-lg-4">
    <div class="card shadow-sm mt-5">
      <div class="card-body p-4">
        <div class="text-center mb-4">
          <i class="bi bi-shield-lock" style="font-size: 2.5rem; color: var(--bs-primary);"></i>
          <h2 class="h4 mt-2 mb-0">Elegí una nueva contraseña</h2>
        </div>

        <%= form_for(resource, as: resource_name, url: password_path(resource_name), html: { method: :put }) do |f| %>
          <%= render "devise/shared/error_messages", resource: resource %>
          <%= f.hidden_field :reset_password_token %>

          <div class="mb-3">
            <%= f.label :password, "Nueva contraseña", class: "form-label" %>
            <% if @minimum_password_length %>
              <div class="form-text"><%= @minimum_password_length %> caracteres como mínimo.</div>
            <% end %>
            <%= f.password_field :password, autofocus: true, autocomplete: "new-password", class: "form-control" %>
          </div>

          <div class="mb-3">
            <%= f.label :password_confirmation, "Confirmar contraseña", class: "form-label" %>
            <%= f.password_field :password_confirmation, autocomplete: "new-password", class: "form-control" %>
          </div>

          <%= f.submit "Cambiar mi contraseña", class: "btn btn-primary w-100" %>
        <% end %>
      </div>
    </div>
  </div>
</div>
```

- [ ] **Step 5: Add the "forgot password" link to the login page**

`app/views/devise/shared/_links.html.erb` isn't rendered anywhere yet (`devise/sessions/new.html.erb` never calls it). Add both the render call and the recoverable link.

In `app/views/devise/shared/_links.html.erb`, add after the existing `registerable` block:

```erb
<%- if devise_mapping.recoverable? && controller_name != 'passwords' && controller_name != 'registrations' %>
  <p><%= link_to "¿Olvidaste tu contraseña?", new_password_path(resource_name) %></p>
<% end %>
```

In `app/views/devise/sessions/new.html.erb`, change:

```erb
          <%= f.submit "Iniciar sesión", class: "btn btn-primary w-100" %>
        <% end %>
      </div>
    </div>
  </div>
</div>
```

to:

```erb
          <%= f.submit "Iniciar sesión", class: "btn btn-primary w-100" %>
        <% end %>

        <div class="text-center mt-3 small">
          <%= render "devise/shared/links" %>
        </div>
      </div>
    </div>
  </div>
</div>
```

- [ ] **Step 6: Run test to verify it passes**

Run: `bin/rails test test/controllers/passwords_flow_test.rb`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add app/views/devise/passwords/new.html.erb app/views/devise/passwords/edit.html.erb app/views/devise/shared/_links.html.erb app/views/devise/sessions/new.html.erb test/controllers/passwords_flow_test.rb
git commit -m "Agregar formularios de recuperación de contraseña"
```

---

### Task 7: Email confirmation web form (confirmable)

**Files:**
- Create: `app/views/devise/confirmations/new.html.erb`
- Modify: `app/views/devise/shared/_links.html.erb`
- Test: `test/controllers/confirmations_flow_test.rb`

**Interfaces:**
- Consumes: Devise route helpers `confirmation_path`, `user_confirmation_path` (already available via `devise_for :users`).

- [ ] **Step 1: Write the failing test**

Create `test/controllers/confirmations_flow_test.rb`:

```ruby
require "test_helper"

class ConfirmationsFlowTest < ActionDispatch::IntegrationTest
  test "unconfirmed user must confirm before signing in" do
    user = User.create!(email: "nuevo@example.com", password: "password123", password_confirmation: "password123", role: "visor")
    assert_not user.confirmed?

    post user_session_path, params: { user: { email: user.email, password: "password123" } }
    assert_redirected_to new_user_session_path
    follow_redirect!
    assert_select ".alert", /confirmar tu correo/

    mail = ActionMailer::Base.deliveries.find { |m| m.to == [user.email] && m.subject == "Instrucciones de confirmación" }
    token = mail.html_part.body.to_s[/confirmation_token=([^"&]+)/, 1]
    assert token.present?

    get user_confirmation_path(confirmation_token: token)
    assert_redirected_to new_user_session_path

    assert user.reload.confirmed?

    post user_session_path, params: { user: { email: user.email, password: "password123" } }
    assert_redirected_to root_path
  end

  test "resend confirmation form renders and re-sends the email" do
    user = User.create!(email: "otro@example.com", password: "password123", password_confirmation: "password123", role: "visor")

    get new_user_confirmation_path
    assert_response :success
    assert_select "h2", "Reenviar confirmación"

    assert_emails 1 do
      post user_confirmation_path, params: { user: { email: user.email } }
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/confirmations_flow_test.rb`
Expected: FAIL — `ActionView::MissingTemplate` for `devise/confirmations/new`.

- [ ] **Step 3: Write the "resend confirmation" form**

Create `app/views/devise/confirmations/new.html.erb`:

```erb
<div class="row justify-content-center">
  <div class="col-md-5 col-lg-4">
    <div class="card shadow-sm mt-5">
      <div class="card-body p-4">
        <div class="text-center mb-4">
          <i class="bi bi-envelope-check" style="font-size: 2.5rem; color: var(--bs-primary);"></i>
          <h2 class="h4 mt-2 mb-0">Reenviar confirmación</h2>
        </div>

        <%= form_for(resource, as: resource_name, url: confirmation_path(resource_name), html: { method: :post }) do |f| %>
          <%= render "devise/shared/error_messages", resource: resource %>

          <div class="mb-3">
            <%= f.label :email, "Correo electrónico", class: "form-label" %>
            <%= f.email_field :email, autofocus: true, autocomplete: "email", class: "form-control" %>
          </div>

          <%= f.submit "Reenviar instrucciones", class: "btn btn-primary w-100" %>
        <% end %>

        <div class="text-center mt-3 small">
          <%= render "devise/shared/links" %>
        </div>
      </div>
    </div>
  </div>
</div>
```

- [ ] **Step 4: Add the "resend confirmation" link**

In `app/views/devise/shared/_links.html.erb`, add after the `recoverable` block from Task 6:

```erb
<%- if devise_mapping.confirmable? && controller_name != 'confirmations' %>
  <p><%= link_to "Reenviar confirmación", new_confirmation_path(resource_name) %></p>
<% end %>
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bin/rails test test/controllers/confirmations_flow_test.rb`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add app/views/devise/confirmations/new.html.erb app/views/devise/shared/_links.html.erb test/controllers/confirmations_flow_test.rb
git commit -m "Agregar formulario de reenvío de confirmación de cuenta"
```

---

### Task 8: Full suite verification

**Files:** none (verification only)

- [ ] **Step 1: Run the full test suite**

Run: `bin/rails test`
Expected: 0 failures, 0 errors. This confirms Tasks 1-7 together — migration, model, config, mailer views, and web forms — don't regress `Admin::UsersController`, `AuthenticationTest`, `NavbarTest`, or any other existing coverage.

- [ ] **Step 2: Manually inspect a rendered email (optional but recommended)**

Run: `bin/rails runner "puts Devise::Mailer.confirmation_instructions(User.first, 'demo-token').html_part.body.to_s"` and paste the output into an HTML file to open in a browser, to eyeball the branded layout renders as expected (no Rails email preview mailer exists in this app yet — this is the lightest way to check without adding one).

- [ ] **Step 3: Commit any fixups**

If Step 1 surfaced fixes, commit them individually with a message describing what broke and why.
