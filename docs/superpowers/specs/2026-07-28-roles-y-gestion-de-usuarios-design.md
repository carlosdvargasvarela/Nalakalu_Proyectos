# Roles y gestión de usuarios (admin-only) — design

## Contexto

Hoy cualquier usuario autenticado puede entrar a `/admin/*` (no hay distinción de rol), y `User` incluye `:registerable`, así que cualquier visitante puede autoregistrarse en `/users/sign_up`. No existe `:recoverable` — no hay flujo de "olvidé mi contraseña".

El pedido: solo administradores pueden crear usuarios, restablecer contraseñas, y (en un trabajo futuro separado) habilitar qué `ProjectType` puede ver cada usuario. Este spec cubre roles + gestión de usuarios únicamente; la visibilidad por tipo de proyecto queda para un spec posterior, una vez que el concepto de rol ya exista.

## Alcance

- **Rol**: `User.role`, un enum Rails (`admin` / `usuario`, default `"usuario"`), pensado para crecer con más roles en el futuro sin cambiar de tipo de columna.
- **Backfill**: `admin@nalakalu.com` (usuario existente) pasa a `admin`; cualquier otro usuario existente (`verify@example.com`) queda en `usuario` (el default).
- **`Admin::UsersController`**: CRUD (`index`, `new`, `create`, `edit`, `update`, `destroy`) en `/admin/users`, mismo patrón que `Admin::InstallersController`. `update` permite cambiar `role` y, opcionalmente, la contraseña (el admin la escribe directamente y se la comunica al usuario por fuera — sin mailer).
- **Autorización**: un `Admin::BaseController` (`ApplicationController` como padre) agrega `before_action :require_admin!`; todos los controladores bajo `app/controllers/admin/` heredan de él en vez de `ApplicationController` directamente. Un usuario `usuario` que intenta acceder a `/admin/*` es redirigido a `root_path` con un alert.
- **Sin auto-registro**: se quita `:registerable` de `User`; `devise_for :users, skip: [:registerable]` en las rutas; se borran las vistas `app/views/devise/registrations/{new,edit}.html.erb` (quedan sin controlador que las sirva); se saca el link "Registrarse" de la navbar.
- **Fixtures**: `juan` (ya usado en los 5 tests de `admin/*`) pasa a `role: admin`. Nuevo fixture `maria` (`role: usuario`) para los tests negativos de autorización.

Fuera de alcance (hoy): visibilidad por `ProjectType` (spec futuro), auto-servicio de cambio de contraseña para el propio usuario, envío de emails, un tercer rol.

## Diseño

### Migración

```ruby
class AddRoleToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :role, :string, default: "usuario", null: false

    reversible do |dir|
      dir.up do
        execute "UPDATE users SET role = 'admin' WHERE email = 'admin@nalakalu.com'"
      end
    end
  end
end
```

### Modelo

```ruby
# app/models/user.rb
class User < ApplicationRecord
  devise :database_authenticatable, :rememberable, :validatable

  enum :role, { usuario: "usuario", admin: "admin" }, default: "usuario"
end
```

### Autorización

```ruby
# app/controllers/admin/base_controller.rb
class Admin::BaseController < ApplicationController
  before_action :require_admin!

  private

  def require_admin!
    return if current_user&.admin?

    redirect_to root_path, alert: "No tenés permiso para acceder a esa sección."
  end
end
```

Cada controlador existente bajo `admin/` (`ProjectTypesController`, `FieldDefinitionsController`, `StageTemplatesController`, `LogEntryTypesController`, `InstallersController`) cambia `class Admin::XController < ApplicationController` por `class Admin::XController < Admin::BaseController`. `Admin::UsersController` (nuevo) hereda de `Admin::BaseController` directamente.

### Rutas

```ruby
devise_for :users, skip: [:registerable]

namespace :admin do
  resources :users
  resources :project_types do
    # ... (sin cambios)
  end
  resources :installers
end
```

### `Admin::UsersController`

```ruby
class Admin::UsersController < Admin::BaseController
  before_action :set_user, only: [:edit, :update, :destroy]

  def index
    @users = User.all
  end

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)
    if @user.save
      redirect_to admin_users_path
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    attrs = user_params
    attrs = attrs.except(:password, :password_confirmation) if attrs[:password].blank?
    if @user.update(attrs)
      redirect_to admin_users_path
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @user.destroy
    redirect_to admin_users_path
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  def user_params
    params.require(:user).permit(:email, :role, :password, :password_confirmation)
  end
end
```

`password`/`password_confirmation` en `create` son obligatorios en la práctica (Devise valida presencia en un registro nuevo); en `update`, si el admin los deja en blanco, no se tocan (mismo patrón que la propia pantalla de Devise "editar cuenta" que se está borrando, pero aplicado del lado admin).

### Vistas

`app/views/admin/users/index.html.erb`, `new.html.erb`, `edit.html.erb`, `_form.html.erb` — mismo patrón Bootstrap que `admin/installers`. La tabla de `index` muestra email + rol + acciones (Editar/Eliminar). El formulario tiene: email, rol (`select` con las dos opciones), contraseña, confirmación de contraseña (estas dos con el hint "dejalo en blanco si no querés cambiarla" en `edit`).

Navbar (`app/views/layouts/_navbar.html.erb`): se saca el link "Registrarse"; se agrega un link "Usuarios" a `admin_users_path`, visible solo si `current_user&.admin?` (igual que "Administración", que ya asume implícitamente que todos son admin hoy — con este cambio ese link también se condiciona a `current_user&.admin?`).

Se borran `app/views/devise/registrations/new.html.erb` y `edit.html.erb` (sin controlador que los sirva una vez que `:registerable` se quita).

## Testing

- Modelo: `User` válido con `role: "usuario"` (default) y `role: "admin"`; enum expone `#admin?`/`#usuario?`.
- Modelo/migración: backfill deja a `admin@nalakalu.com` en `admin` (test de integración vía `bin/rails runner`, no automatizado — sin precedente de tests de migración en este repo, igual que las migraciones anteriores).
- `Admin::BaseController` (vía cualquier controlador admin existente, p. ej. `Admin::InstallersController`): un usuario `usuario` (fixture `maria`) que intenta `GET /admin/installers` es redirigido a `root_path` con el alert; un usuario `admin` (fixture `juan`) accede normalmente. Los 5 test files de `admin/*` ya usan `sign_in users(:juan)` — pasan sin cambios una vez que `juan` es `admin`.
- `Admin::UsersController`: create/update/destroy, incluyendo que `update` sin contraseña no la modifica, y que un `usuario` no-admin recibe 302 redirect en cualquier acción.
- Rutas: `GET /users/sign_up` ya no existe (404 o rutas no generadas — `devise_for skip: [:registerable]` no define esa ruta en absoluto, así que un test de "la ruta no existe" es más apropiado que un test de respuesta HTTP).
- Vista: navbar no muestra "Registrarse"; muestra "Usuarios" solo para `current_user.admin?`.

## Edge cases

- Un admin no puede quedar sin ningún admin en el sistema por accidente (ej. el único admin se cambia a sí mismo a `usuario`, o se borra a sí mismo) — **fuera de alcance**: no se agrega esa validación hoy (el piloto tiene un solo admin conocido y esto es un caso de uso de administración manual, no una garantía que el sistema deba imponer todavía).
- Un usuario `usuario` que ya tenía una sesión activa antes de este cambio y trata de ir a `/admin/algo`: el `before_action :require_admin!` corta en el próximo request, no requiere invalidar sesiones existentes.
- `verify@example.com` (el segundo usuario existente en el piloto) queda en `usuario` tras el backfill — si en realidad debía ser admin, se corrige a mano desde el nuevo panel `/admin/users` una vez desplegado.
