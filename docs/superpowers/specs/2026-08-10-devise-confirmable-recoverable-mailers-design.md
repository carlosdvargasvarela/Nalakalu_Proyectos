# Devise: recuperar contraseña, confirmación de email, y emails modernos

## Contexto

`User` (app/models/user.rb:4) solo usa `:database_authenticatable,
:rememberable, :validatable`. No hay `:recoverable` ni `:confirmable`, así
que Devise nunca dispara un mailer hoy — por eso no existen vistas de
mailer ni de "olvidé mi contraseña" / "confirmar cuenta".

`devise_for :users, skip: [:registerable]` (config/routes.rb:2): no hay
auto-registro, los usuarios se crean solo desde `Admin::UsersController`
(app/controllers/admin/users_controller.rb), donde el admin ya define la
contraseña inicial en el formulario. Esto no cambia con este trabajo:
`:confirmable` se agrega como paso de verificación de email adicional, no
como reemplazo del flujo de creación.

SMTP de producción y el mailer base ya quedaron configurados en trabajo
previo (config/environments/production.rb, app/mailers/application_mailer.rb,
config/initializers/devise.rb:27,33 ya apunta `parent_mailer` a
`ApplicationMailer`).

## Cambio

### 1. Modelo y migración

- `User`: `devise :database_authenticatable, :rememberable, :validatable,
  :recoverable, :confirmable`.
- Migración que agrega las columnas de `:confirmable` a `users`:
  `confirmation_token` (string, índice único), `confirmed_at` (datetime),
  `confirmation_sent_at` (datetime), `unconfirmed_email` (string).
  `:recoverable` no necesita columnas nuevas — `reset_password_token` y
  `reset_password_sent_at` ya existen en el schema (db/schema.rb:245-246).
- La misma migración hace backfill:
  `User.update_all(confirmed_at: Time.current)` para toda fila con
  `confirmed_at IS NULL` en el momento de correrla (usando un modelo
  scoped a la migración, no `User` real — ver la nota de memoria sobre
  migraciones de datos). Así ningún usuario existente queda bloqueado;
  solo los usuarios creados después de este cambio deberán confirmar su
  email antes de loguearse.

### 2. Config Devise (config/initializers/devise.rb)

- `config.send_password_change_notification = true` (línea ~135, hoy
  comentada) — avisa por correo cuando cambia la contraseña.
- `config.send_email_changed_notification = true` (línea ~132, hoy
  comentada) — avisa al email viejo cuando se solicita un cambio de email.
- `config.reconfirmable` ya está en `true` — se deja así: cambiar el email
  requiere confirmar el nuevo antes de aplicarlo.
- No se toca `allow_unconfirmed_access_for` (queda en su default de Devise,
  0 — sin gracia, debe confirmar antes de loguearse la primera vez) ni
  `confirm_within`.

### 3. Vistas web (formularios de Devise, no el email)

Estilo Bootstrap 5 igual a `app/views/devise/sessions/new.html.erb`
(card centrada, `form-control`, `btn btn-primary`):

- `app/views/devise/passwords/new.html.erb` — pedir email para recuperar.
- `app/views/devise/passwords/edit.html.erb` — nueva contraseña con el
  token del link.
- `app/views/devise/confirmations/new.html.erb` — reenviar instrucciones
  de confirmación.
- `app/views/devise/shared/_links.html.erb` — agregar "¿Olvidaste tu
  contraseña?" (`new_password_path`) y "Reenviar confirmación"
  (`new_confirmation_path`), ambos condicionados a
  `devise_mapping.recoverable?` / `.confirmable?` igual que ya hace el
  link de registro con `devise_mapping.registerable?`.

### 4. Emails: layout moderno reusable

Reescribir `app/views/layouts/mailer.html.erb`: header con wordmark
"Nalakalu" en texto (sin logo-imagen, evita el problema de imágenes rotas
en clientes de correo) sobre el color de marca `#2563EB`
(app/assets/stylesheets/application.css:18), tarjeta blanca centrada con
`max-width` fijo para legibilidad, botón CTA sólido (mismo color de
marca), footer gris pequeño con disclaimer ("Si no solicitaste esto,
podés ignorar este correo"). Todo el CSS inline — obligatorio para
Gmail/Outlook, que ignoran o strippean `<style>` en el `<head>` según el
cliente.

`app/views/layouts/mailer.text.erb` se mantiene simple (ya es solo
`<%= yield %>`, correcto para texto plano).

Vistas de contenido nuevas, en español, todas sobre ese layout, versión
`.html.erb` y `.text.erb`:

- `devise/mailer/confirmation_instructions` — "Confirmá tu cuenta",
  botón al link de confirmación.
- `devise/mailer/reset_password_instructions` — "Restablecé tu
  contraseña", botón al link, mención de expiración (`reset_password_within`,
  ya en 6 horas).
- `devise/mailer/password_change` — aviso informativo (sin botón) de que
  la contraseña cambió, con hora del cambio.
- `devise/mailer/email_changed` — aviso informativo (sin botón) de que se
  pidió cambiar el email, enviado al email viejo.

## Fuera de alcance

- No se toca el flujo de creación de usuarios en `Admin::UsersController`
  ni su formulario — el admin sigue definiendo la contraseña inicial.
- No se habilita `:registerable` ni auto-registro.
- No se agrega `:lockable`, `:timeoutable` ni `:trackable`.
- No se embebe un logo como imagen — wordmark en texto/CSS.
- Deploy y config vars de Heroku (`SMTP_USERNAME`, `SMTP_PASSWORD`,
  `APP_HOST`) las maneja el usuario directamente, no es parte de este
  trabajo.

## Testing

- `test/fixtures/users.yml`: agregar `confirmed_at: <%= Time.current %>` a
  las 4 filas (juan, carla, maria, pedro). El helper `sign_in` de
  `Devise::Test::IntegrationHelpers` bypasea la autenticación real (setea
  la sesión de Warden directo), así que la suite existente no se rompe sin
  esto — pero los tests nuevos de este plan sí necesitan usuarios
  confirmados para loguearse por el flujo real (POST a
  `user_session_path`) después de un reset de contraseña o una
  confirmación.
- Test de modelo: `User` con `:recoverable`/`:confirmable` responde a
  `confirmed?` / `send_reset_password_instructions` (ya cubierto por los
  tests que Devise agrega vía `Devise::Test::Mailer`/`ActionMailer::TestHelper`
  si se usan; si no, un test directo mínimo).
- Test de la migración: correr la suite completa de migraciones desde cero
  contra la DB de test confirma que el backfill no rompe ninguna migración
  posterior (ver nota de memoria sobre migraciones de datos y modelos
  scoped).
- Test de controlador/integración: `Admin::UsersController#create` sigue
  creando un usuario funcional (con `confirmed_at: nil` ahora, ya no
  puede loguearse hasta confirmar) — ajustar cualquier test existente que
  loguee un usuario recién creado por `admin/users` sin pasar por
  confirmación.
- Test de mailer: `ApplicationMailer`/`Devise::Mailer` para cada una de
  las 4 vistas nuevas — que rendericen sin error y que el asunto/CTA
  tengan el contenido esperado (smoke test, no snapshot de HTML).
