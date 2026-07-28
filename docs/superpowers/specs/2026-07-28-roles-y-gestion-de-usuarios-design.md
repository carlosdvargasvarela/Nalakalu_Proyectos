# Roles y permisos por proyecto — design

## Contexto

Hoy cualquier usuario autenticado puede entrar a `/admin/*` y editar cualquier `Project` (no hay ninguna distinción de rol ni de acceso). `User` incluye `:registerable`, así que cualquier visitante puede autoregistrarse en `/users/sign_up`. No existe `:recoverable` — no hay flujo de "olvidé mi contraseña".

El pedido final (reemplaza el borrador anterior de este mismo documento, que solo contemplaba admin/usuario binario): tres roles con permisos bien distintos:

- **admin**: crea tipos de proyecto (y toda la configuración bajo `/admin/*`: subprocesos, campos, instaladores, tipos de bitácora, usuarios) y tiene acceso total a todo.
- **gerente**: no puede tocar `/admin/*` (nada de tipos de proyecto ni configuración). Puede **ver todos los proyectos**, pero solo **editar** aquellos donde un admin le dio permiso explícito. Si el gerente crea un proyecto nuevo, queda con permiso de edición sobre ese proyecto automáticamente.
- **visor**: solo puede **ver** los proyectos puntuales a los que un admin lo agregó (ni siquiera ve el resto del listado). Nunca edita nada.

**Supuesto a confirmar**: `/admin/*` completo (no solo "crear tipos de proyecto") queda exclusivo de `admin` — el gerente no entra a ninguna pantalla de configuración, ni siquiera en modo lectura. Si el gerente debía poder, por ejemplo, ver (sin editar) los subprocesos o instaladores, avisar antes de implementar.

## Alcance

- **Rol**: `User.role`, enum Rails (`admin` / `gerente` / `visor`, default `"visor"` — el más restrictivo, para que un usuario nuevo sin rol asignado explícitamente nunca vea de más).
- **Backfill**: `admin@nalakalu.com` (usuario existente) pasa a `admin`; `verify@example.com` queda en `visor` (el default) — se puede reasignar a mano después desde `/admin/users`.
- **Permisos por proyecto**: tabla `project_accesses` (`user_id`, `project_id`, `can_edit:boolean`). Su significado depende del rol del usuario dueño de la fila:
  - **gerente**: ya ve todos los proyectos por rol (no necesita fila para ver); una fila con `can_edit: true` es lo único que habilita edición sobre ESE proyecto puntual.
  - **visor**: la sola existencia de una fila (sin importar `can_edit`) habilita ver ESE proyecto; nunca puede editar, la columna `can_edit` se ignora para este rol si llegara a estar en `true`.
  - **admin**: no usa esta tabla — acceso total siempre, sin filas.
- **`Admin::UsersController`**: CRUD (`index`, `new`, `create`, `edit`, `update`, `destroy`) en `/admin/users`, mismo patrón que `Admin::InstallersController`. `update` permite cambiar `role`, la contraseña (opcional, el admin la escribe directamente — sin mailer) y los accesos por proyecto (ver más abajo).
- **Autorización**: `Admin::BaseController` (todos los controladores de `admin/` heredan de él) exige `admin?`. `ProjectsController` filtra el índice/seguimiento por lo que el usuario puede ver, y bloquea `show`/`edit`/`update` según `can_view_project?`/`can_edit_project?`. `LogEntriesController#create` exige `can_edit_project?`. `ImportsController` (crea proyectos en lote) exige admin o gerente.
- **Sin auto-registro**: se quita `:registerable` de `User`; `devise_for :users, skip: [:registerable]`; se borran las vistas `app/views/devise/registrations/{new,edit}.html.erb`; se saca el link "Registrarse" de la navbar.
- **Fixtures**: `juan` pasa a `role: admin` (ya usado en los 5 tests de `admin/*`, así siguen pasando sin tocar esos archivos). Nuevos fixtures `carla` (`role: gerente`) y `maria` (`role: visor`) para los tests de autorización por rol.

Fuera de alcance: auto-servicio de cambio de contraseña, envío de emails, un cuarto rol, UI para asignar accesos desde la ficha del proyecto (se hace únicamente desde la ficha del usuario, según lo elegido), validar que siempre quede al menos un admin en el sistema.

## Diseño

### Migraciones

```ruby
class AddRoleToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :role, :string, default: "visor", null: false

    reversible do |dir|
      dir.up { execute "UPDATE users SET role = 'admin' WHERE email = 'admin@nalakalu.com'" }
    end
  end
end
```

```ruby
class CreateProjectAccesses < ActiveRecord::Migration[7.2]
  def change
    create_table :project_accesses do |t|
      t.references :user, null: false, foreign_key: true
      t.references :project, null: false, foreign_key: true
      t.boolean :can_edit, null: false, default: false

      t.timestamps

      t.index [:user_id, :project_id], unique: true
    end
  end
end
```

### Modelos

```ruby
# app/models/user.rb
class User < ApplicationRecord
  devise :database_authenticatable, :rememberable, :validatable

  enum :role, { admin: "admin", gerente: "gerente", visor: "visor" }, default: "visor"

  has_many :project_accesses, dependent: :destroy
  has_many :accessible_projects, through: :project_accesses, source: :project

  def can_view_project?(project)
    return true if admin? || gerente?
    project_accesses.exists?(project_id: project.id)
  end

  def can_edit_project?(project)
    return true if admin?
    return false if visor?
    project_accesses.exists?(project_id: project.id, can_edit: true)
  end
end
```

```ruby
# app/models/project_access.rb
class ProjectAccess < ApplicationRecord
  belongs_to :user
  belongs_to :project

  validates :user_id, uniqueness: { scope: :project_id }
end
```

```ruby
# app/models/project.rb — agregar
has_many :project_accesses, dependent: :destroy

def self.visible_to(user)
  return all if user.admin? || user.gerente?
  joins(:project_accesses).where(project_accesses: { user_id: user.id })
end
```

### Autorización en controladores

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

Todos los controladores bajo `app/controllers/admin/` (incluido el nuevo `UsersController`) heredan de `Admin::BaseController` en vez de `ApplicationController`.

`ProjectsController`:
- `index`/`build_section` y `tracker`: la query base pasa de `Project.where(...)` a `Project.visible_to(current_user).where(...)`.
- `show`: `before_action` que hace `redirect_to projects_path, alert: "..."` si `!current_user.can_view_project?(@project)`.
- `edit`/`update`: mismo chequeo con `can_edit_project?`.
- `new`/`create`: `before_action :require_admin_or_gerente!` (visor nunca crea proyectos). Tras `@project.save` exitoso, si `current_user.gerente?`, se crea `ProjectAccess.create!(user: current_user, project: @project, can_edit: true)`.
- `bulk_assign_installer`: mismo `require_admin_or_gerente!`, y el `Project.where(id: project_ids)` se cruza con `Project.visible_to(current_user)` filtrando además por editable (`can_edit_project?`) antes de tocar cada uno — un gerente no puede reasignar instalador en un proyecto que no puede editar.

`show.html.erb`: los botones "Editar" y archivar, el formulario de la tabla de subprocesos, y el formulario para agregar bitácora se ocultan (`if current_user.can_edit_project?(@project)`); el historial de cambios y el listado de bitácora quedan visibles en modo lectura para cualquiera que pueda ver el proyecto.

`LogEntriesController#create`: `before_action` exige `can_edit_project?(@project)` (visor y gerente sin permiso no pueden agregar notas). `destroy` no cambia (ya exige ser el autor).

`ImportsController`: gana el mismo `before_action :require_admin_or_gerente!`. Tras crear cada `Project` exitosamente en el loop, si `current_user.gerente?`, se le otorga `ProjectAccess` igual que en `ProjectsController#create`.

`require_admin_or_gerente!` se define una sola vez, en `ApplicationController`, para reusarlo desde `ProjectsController` e `ImportsController`.

### `Admin::UsersController` y asignación de accesos

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
    @projects = Project.all.includes(:project_type)
  end

  def update
    attrs = user_params
    attrs = attrs.except(:password, :password_confirmation) if attrs[:password].blank?
    if @user.update(attrs)
      sync_project_accesses!
      redirect_to admin_users_path
    else
      @projects = Project.all.includes(:project_type)
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

  # ponytail: reemplaza todos los accesos del usuario en cada guardado — O(proyectos
  # totales), aceptable a la escala de este piloto. Si la cantidad de proyectos crece
  # mucho, upgrade a un diff (solo crear/borrar lo que cambió) en vez de destroy_all+create.
  def sync_project_accesses!
    submitted = params.fetch(:project_access, {})
    @user.project_accesses.destroy_all
    submitted.each do |project_id, flags|
      next unless flags["view"] == "1"
      @user.project_accesses.create!(project_id: project_id, can_edit: flags["edit"] == "1")
    end
  end
end
```

`edit.html.erb` agrega, debajo del formulario de email/rol/contraseña, una tabla con una fila por `Project` (agrupado por `project_type.name` para que sea navegable) con dos checkboxes por fila: "Ver" (`project_access[<id>][view]`) y "Editar" (`project_access[<id>][edit]`), pre-marcados según `@user.project_accesses`. El checkbox "Editar" no tiene efecto si el usuario es `visor` (ver Diseño de modelos) — se muestra igual para simplicidad, sin JS condicional por rol.

### Rutas

```ruby
devise_for :users, skip: [:registerable]

namespace :admin do
  resources :users
  # ... (project_types, installers sin cambios)
end
```

### Navbar

Se saca "Registrarse". Se agrega "Usuarios" a `admin_users_path`, visible solo si `current_user&.admin?` (mismo criterio que "Administración").

## Testing

- Modelo: `User#can_view_project?`/`#can_edit_project?` para cada combinación de rol × (sin fila / fila view / fila can_edit) × dueño-vs-no-dueño.
- Modelo: `Project.visible_to(user)` devuelve todos para admin/gerente, solo los asignados para visor.
- `Admin::BaseController`: `carla` (gerente) y `maria` (visor) reciben redirect en cualquier ruta `/admin/*`; `juan` (admin) accede.
- `ProjectsController`: `maria` (visor) sin acceso a un proyecto recibe redirect en `show`; con `ProjectAccess` (sin `can_edit`) puede ver pero `edit`/`update` la redirigen; `carla` (gerente) ve cualquier proyecto en `index`/`show`, pero solo edita los que tienen `ProjectAccess(can_edit: true)`; crear un proyecto como `carla` genera automáticamente su propio `ProjectAccess(can_edit: true)`.
- `LogEntriesController#create`: `maria` (visor) no puede crear una nota aunque tenga acceso de vista; `carla` sin `can_edit` en ese proyecto tampoco puede.
- `Admin::UsersController`: `update` con `project_access` params crea/reemplaza las filas correctamente; un `visor` con acceso a 2 proyectos ve exactamente esos 2 en `index`.
- Rutas: `/users/sign_up` no existe.

## Edge cases

- Un admin puede quedar sin ningún otro admin en el sistema (se autodegrada o se borra) — fuera de alcance, sin validación hoy.
- Cambiar el rol de un usuario de `gerente` a `visor` no borra sus `ProjectAccess` existentes — las filas quedan igual, solo cambia cómo se interpretan (de "edición puntual" pasan a "solo ver esos mismos proyectos"). Es el comportamiento esperado dado el diseño, no un caso a manejar aparte.
- Bulk-import (`ImportsController`) ejecutado por un `gerente`: cada fila creada le otorga acceso de edición individualmente (un `ProjectAccess` por proyecto creado), igual que crear uno por uno a mano.
