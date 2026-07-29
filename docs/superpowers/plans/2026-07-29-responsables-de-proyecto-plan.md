# Responsables de proyecto Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single "instalador" reference field with a full multi-responsible model: a `Project` can have many `Responsible`s, each of a `ResponsibleType` (configured per `ProjectType`), applying either to the whole project or to one `ProjectStage`. A `Responsible` can optionally be linked to a `User`, who then gets a new `responsable` role that shows only their assigned projects and lets them edit the `progress_percent` of their assigned stages.

**Architecture:** Three new tables (`responsible_types`, `responsibles`, `project_responsibles`) replace the `installers` table and the `custom_fields`-based reference field. `ProjectResponsible` is the join: `project` + `responsible` + `responsible_type`, with an optional `project_stage` (nil = whole project). Authorization (`User#can_view_project?`, `Project.visible_to`, and a new `User#editable_project_stage_ids`) is extended to resolve access through this join for the new `responsable` role, alongside the existing admin/gerente/visor logic. The last task migrates existing `Installer` data into the new tables and removes `Installer` entirely.

**Tech Stack:** Rails 7.2, Minitest with fixtures, Bootstrap tables/cards (`admin_card` helper), vanilla server-rendered forms (no JS framework, consistent with the rest of the app).

## Global Constraints

- A `Responsible`'s type is chosen per assignment (`ProjectResponsible#responsible_type`), never fixed on the `Responsible` record itself — the same person can be "Instalador" on one project and "Diseñador" on another.
- `ResponsibleType` is scoped to a `ProjectType` (like `FieldDefinition`/`StageTemplate`), not global.
- A `responsable`-role user with a project-wide assignment (`project_stage_id: nil`) can edit `progress_percent` on **every** stage of that project. One assigned to a specific stage can edit only that stage's `progress_percent`. Nothing else on the project (name, custom fields, dates) is ever editable by this role.
- `can_edit_project?` (full edit: name, custom fields, all stage dates+progress) is unchanged in meaning — still exclusive to admin/gerente-with-access. The new `responsable` role never gets `can_edit_project?` returning true; it gets scoped access through the new `editable_project_stage_ids` method instead.
- The real stage-progress editing surface in this app is the `_stage_table` partial and the interactive Gantt on `projects/show.html.erb` — both submit to `ProjectsController#update` (PATCH `/projects/:id`), **not** to the `edit`/`_form` page (which only ever edits `name` + `custom_fields`, no stage data). Task 6 below adds a role-aware second partial for the `responsable` case; it does not touch `edit.html.erb`/`_form.html.erb`.
- No new JS dependency. No soft-delete anywhere in this app — deleting a `Responsible` or `ResponsibleType` cascades to its `ProjectResponsible` rows (`dependent: :destroy`), matching how the rest of the app handles deletion.
- Every new admin-facing model needs a Spanish label in `config/locales/es.yml` (`activerecord.models` + `activerecord.attributes`), matching the existing `installer`/`log_entry_type` entries.

---

### Task 1: Data model — `ResponsibleType`, `Responsible`, `ProjectResponsible`

**Files:**
- Create: `db/migrate/<timestamp>_create_responsible_types.rb`
- Create: `db/migrate/<timestamp>_create_responsibles.rb`
- Create: `db/migrate/<timestamp>_create_project_responsibles.rb`
- Create: `app/models/responsible_type.rb`
- Create: `app/models/responsible.rb`
- Create: `app/models/project_responsible.rb`
- Modify: `app/models/project.rb`
- Modify: `app/models/project_stage.rb`
- Modify: `config/locales/es.yml`
- Test: `test/models/responsible_type_test.rb`
- Test: `test/models/responsible_test.rb`
- Test: `test/models/project_responsible_test.rb`
- Test: `test/fixtures/responsible_types.yml`
- Test: `test/fixtures/responsibles.yml`

**Interfaces:**
- Produces: `ResponsibleType` (`belongs_to :project_type`, `name`), `Responsible` (`name`, `color`, `belongs_to :user, optional: true`), `ProjectResponsible` (`belongs_to :project, :responsible, :responsible_type`, `belongs_to :project_stage, optional: true`, `#project_wide?`), `Project#project_responsibles`, `Project#responsible_for(responsible_type)`, `ProjectStage#project_responsibles`.

- [ ] **Step 1: Write the failing model tests**

```ruby
# test/models/responsible_type_test.rb
require "test_helper"

class ResponsibleTypeTest < ActiveSupport::TestCase
  test "valid with name and project_type" do
    type = ResponsibleType.new(project_type: project_types(:instalaciones), name: "Instalador")
    assert type.valid?
  end

  test "invalid without name" do
    type = ResponsibleType.new(project_type: project_types(:instalaciones))
    assert_not type.valid?
  end

  test "invalid with a duplicate name within the same project_type" do
    ResponsibleType.create!(project_type: project_types(:instalaciones), name: "Instalador")
    dup = ResponsibleType.new(project_type: project_types(:instalaciones), name: "Instalador")
    assert_not dup.valid?
  end

  test "valid with the same name in a different project_type" do
    ResponsibleType.create!(project_type: project_types(:instalaciones), name: "Instalador")
    other_type = ProjectType.create!(name: "Mantenimiento", slug: "mantenimiento")
    assert ResponsibleType.new(project_type: other_type, name: "Instalador").valid?
  end
end
```

```ruby
# test/models/responsible_test.rb
require "test_helper"

class ResponsibleTest < ActiveSupport::TestCase
  test "valid with name" do
    assert Responsible.new(name: "Ana Gómez").valid?
  end

  test "invalid without name" do
    assert_not Responsible.new.valid?
  end

  test "valid with default color" do
    responsible = Responsible.new(name: "Ana Gómez")
    assert responsible.valid?
    assert_equal "#6c757d", responsible.color
  end

  test "invalid with a malformed color" do
    assert_not Responsible.new(name: "Ana Gómez", color: "blue").valid?
  end

  test "valid without a linked user" do
    assert Responsible.new(name: "Ana Gómez", user: nil).valid?
  end

  test "invalid when the linked user is already linked to another responsible" do
    Responsible.create!(name: "Ana Gómez", user: users(:maria))
    dup = Responsible.new(name: "Otra Persona", user: users(:maria))
    assert_not dup.valid?
  end
end
```

```ruby
# test/models/project_responsible_test.rb
require "test_helper"

class ProjectResponsibleTest < ActiveSupport::TestCase
  setup do
    @project_type = project_types(:instalaciones)
    @responsible_type = ResponsibleType.create!(project_type: @project_type, name: "Instalador")
    @responsible = Responsible.create!(name: "Ana Gómez")
    @project = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: {})
  end

  test "valid at project level (no stage)" do
    pr = ProjectResponsible.new(project: @project, responsible: @responsible, responsible_type: @responsible_type)
    assert pr.valid?
    assert pr.project_wide?
  end

  test "valid scoped to one of the project's stages" do
    stage = @project.project_stages.first
    pr = ProjectResponsible.new(project: @project, responsible: @responsible, responsible_type: @responsible_type, project_stage: stage)
    assert pr.valid?
    assert_not pr.project_wide?
  end

  test "invalid with a duplicate responsible/type/stage combination" do
    ProjectResponsible.create!(project: @project, responsible: @responsible, responsible_type: @responsible_type)
    dup = ProjectResponsible.new(project: @project, responsible: @responsible, responsible_type: @responsible_type)
    assert_not dup.valid?
  end

  test "valid with the same responsible/type at project level and at a specific stage" do
    ProjectResponsible.create!(project: @project, responsible: @responsible, responsible_type: @responsible_type)
    scoped = ProjectResponsible.new(
      project: @project, responsible: @responsible, responsible_type: @responsible_type,
      project_stage: @project.project_stages.first
    )
    assert scoped.valid?
  end

  test "invalid when project_stage belongs to a different project" do
    other_project = Project.create!(project_type: @project_type, name: "Torre Sur", custom_fields: {})
    pr = ProjectResponsible.new(
      project: @project, responsible: @responsible, responsible_type: @responsible_type,
      project_stage: other_project.project_stages.first
    )
    assert_not pr.valid?
  end

  test "invalid when responsible_type belongs to a different project_type" do
    other_type = ProjectType.create!(name: "Mantenimiento", slug: "mantenimiento")
    foreign_responsible_type = ResponsibleType.create!(project_type: other_type, name: "Instalador")
    pr = ProjectResponsible.new(project: @project, responsible: @responsible, responsible_type: foreign_responsible_type)
    assert_not pr.valid?
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/models/responsible_type_test.rb test/models/responsible_test.rb test/models/project_responsible_test.rb`
Expected: FAIL — uninitialized constants.

- [ ] **Step 3: Generate and edit the migrations**

```ruby
# db/migrate/<timestamp>_create_responsible_types.rb
class CreateResponsibleTypes < ActiveRecord::Migration[7.2]
  def change
    create_table :responsible_types do |t|
      t.references :project_type, null: false, foreign_key: true
      t.string :name, null: false
      t.timestamps
      t.index [:project_type_id, :name], unique: true
    end
  end
end
```

```ruby
# db/migrate/<timestamp>_create_responsibles.rb
class CreateResponsibles < ActiveRecord::Migration[7.2]
  def change
    create_table :responsibles do |t|
      t.string :name, null: false
      t.string :color, default: "#6c757d", null: false
      t.references :user, null: true, foreign_key: true
      t.timestamps
      t.index [:user_id], unique: true
    end
  end
end
```

```ruby
# db/migrate/<timestamp>_create_project_responsibles.rb
class CreateProjectResponsibles < ActiveRecord::Migration[7.2]
  def change
    create_table :project_responsibles do |t|
      t.references :project, null: false, foreign_key: true
      t.references :responsible, null: false, foreign_key: true
      t.references :responsible_type, null: false, foreign_key: true
      t.references :project_stage, null: true, foreign_key: true
      t.timestamps
      t.index [:project_id, :responsible_id, :responsible_type_id, :project_stage_id],
        unique: true, name: "index_project_responsibles_on_assignment"
    end
  end
end
```

Run: `bin/rails db:migrate`

- [ ] **Step 4: Create the models**

```ruby
# app/models/responsible_type.rb
class ResponsibleType < ApplicationRecord
  belongs_to :project_type
  has_many :project_responsibles, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :project_type_id }
end
```

```ruby
# app/models/responsible.rb
class Responsible < ApplicationRecord
  belongs_to :user, optional: true
  has_many :project_responsibles, dependent: :destroy

  validates :name, presence: true
  validates :color, format: { with: /\A#[0-9a-fA-F]{6}\z/, message: "debe ser un color hexadecimal (ej. #6c757d)" }
  validates :user_id, uniqueness: true, allow_nil: true
end
```

```ruby
# app/models/project_responsible.rb
class ProjectResponsible < ApplicationRecord
  belongs_to :project
  belongs_to :responsible
  belongs_to :responsible_type
  belongs_to :project_stage, optional: true

  validates :responsible_id, uniqueness: { scope: [:project_id, :responsible_type_id, :project_stage_id] }
  validate :project_stage_belongs_to_project
  validate :responsible_type_belongs_to_project_type

  def project_wide?
    project_stage_id.nil?
  end

  private

  def project_stage_belongs_to_project
    return if project_stage.nil? || project.nil?
    errors.add(:project_stage, "debe pertenecer al mismo proyecto") unless project_stage.project_id == project.id
  end

  def responsible_type_belongs_to_project_type
    return if responsible_type.nil? || project.nil?
    errors.add(:responsible_type, "debe pertenecer al tipo de este proyecto") unless responsible_type.project_type_id == project.project_type_id
  end
end
```

- [ ] **Step 5: Wire up `Project` and `ProjectStage`**

In `app/models/project.rb`, add next to `has_many :project_accesses, dependent: :destroy`:

```ruby
  has_many :project_responsibles, dependent: :destroy
```

And add this public method (near `installer`, which a later task removes):

```ruby
  def responsible_for(responsible_type)
    project_responsibles.find { |pr| pr.responsible_type_id == responsible_type.id && pr.project_wide? }&.responsible
  end
```

In `app/models/project_stage.rb`, add next to `belongs_to :user, optional: true`:

```ruby
  has_many :project_responsibles, dependent: :destroy
```

- [ ] **Step 6: Add Spanish labels**

In `config/locales/es.yml`, under `activerecord.models` (after `installer: "Instalador"`):

```yaml
      responsible_type: "Tipo de responsable"
      responsible: "Responsable"
      project_responsible: "Responsable de proyecto"
```

Under `activerecord.attributes` (after the `installer:` block):

```yaml
      responsible_type:
        name: "Nombre"
      responsible:
        name: "Nombre"
        color: "Color"
```

- [ ] **Step 7: Add fixtures**

```yaml
# test/fixtures/responsible_types.yml
instalador:
  project_type_id: <%= ActiveRecord::FixtureSet.identify(:instalaciones) %>
  name: Instalador
  created_at: <%= Time.current %>
  updated_at: <%= Time.current %>

disenador:
  project_type_id: <%= ActiveRecord::FixtureSet.identify(:instalaciones) %>
  name: Diseñador
  created_at: <%= Time.current %>
  updated_at: <%= Time.current %>
```

```yaml
# test/fixtures/responsibles.yml
ana_gomez:
  name: Ana Gómez
  color: "#6c757d"
  created_at: <%= Time.current %>
  updated_at: <%= Time.current %>
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `bin/rails test test/models/responsible_type_test.rb test/models/responsible_test.rb test/models/project_responsible_test.rb`
Expected: PASS

- [ ] **Step 9: Commit**

```bash
git add db/migrate db/schema.rb app/models/responsible_type.rb app/models/responsible.rb app/models/project_responsible.rb \
  app/models/project.rb app/models/project_stage.rb config/locales/es.yml \
  test/models/responsible_type_test.rb test/models/responsible_test.rb test/models/project_responsible_test.rb \
  test/fixtures/responsible_types.yml test/fixtures/responsibles.yml
git commit -m "Add ResponsibleType, Responsible, and ProjectResponsible models"
```

---

### Task 2: `responsable` role and authorization

**Files:**
- Modify: `app/models/user.rb`
- Modify: `app/models/project.rb`
- Modify: `app/helpers/application_helper.rb`
- Test: `test/models/user_test.rb`
- Test: `test/models/project_test.rb`
- Test: `test/fixtures/users.yml`
- Test: `test/fixtures/responsibles.yml`

**Interfaces:**
- Consumes: `ProjectResponsible`, `Responsible` (Task 1).
- Produces: `User#responsible` (has_one), `User.roles` including `"responsable"`, `User#can_view_project?` extended, `Project.visible_to` extended, `User#editable_project_stage_ids(project) -> Array<Integer>`.

- [ ] **Step 1: Add fixtures for the new role**

Add to `test/fixtures/users.yml`:

```yaml

pedro:
  email: pedro@example.com
  encrypted_password: <%= Devise::Encryptor.digest(User, "password123") %>
  role: responsable
```

Add to `test/fixtures/responsibles.yml`:

```yaml

pedro_responsable:
  name: Pedro Instalador
  color: "#6c757d"
  user_id: <%= ActiveRecord::FixtureSet.identify(:pedro) %>
  created_at: <%= Time.current %>
  updated_at: <%= Time.current %>
```

- [ ] **Step 2: Write the failing tests**

Add to `test/models/user_test.rb`, inside `class UserTest`:

```ruby
  test "role accepts responsable" do
    assert User.new(role: "responsable").responsable?
  end

  test "responsable with a project-wide assignment can view the project and edit every stage" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    responsable = users(:pedro)
    ProjectResponsible.create!(
      project: project, responsible: responsable.responsible,
      responsible_type: responsible_types(:instalador)
    )

    assert responsable.can_view_project?(project)
    assert_not responsable.can_edit_project?(project)
    assert_equal project.project_stage_ids.sort, responsable.editable_project_stage_ids(project).sort
  end

  test "responsable assigned to a single stage can only edit that stage" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    stage = project.project_stages.first
    responsable = users(:pedro)
    ProjectResponsible.create!(
      project: project, responsible: responsable.responsible,
      responsible_type: responsible_types(:instalador), project_stage: stage
    )

    assert responsable.can_view_project?(project)
    assert_equal [stage.id], responsable.editable_project_stage_ids(project)
  end

  test "responsable without any assignment cannot view the project and has nothing editable" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    responsable = users(:pedro)

    assert_not responsable.can_view_project?(project)
    assert_equal [], responsable.editable_project_stage_ids(project)
  end

  test "responsable role with no linked Responsible record sees and can edit nothing" do
    unlinked = User.create!(email: "sin-vinculo@example.com", password: "password123", role: "responsable")
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})

    assert_not unlinked.can_view_project?(project)
    assert_equal [], unlinked.editable_project_stage_ids(project)
  end

  test "admin and gerente-with-access editable_project_stage_ids covers every stage" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    assert_equal project.project_stage_ids.sort, users(:juan).editable_project_stage_ids(project).sort

    gerente = users(:carla)
    ProjectAccess.create!(user: gerente, project: project, can_edit: true)
    assert_equal project.project_stage_ids.sort, gerente.editable_project_stage_ids(project).sort
  end

  test "gerente without edit access has nothing editable" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    assert_equal [], users(:carla).editable_project_stage_ids(project)
  end
```

Add to `test/models/project_test.rb`, inside `class ProjectTest`:

```ruby
  test "visible_to a responsable only returns projects with an assignment" do
    assigned = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: {})
    Project.create!(project_type: @project_type, name: "Torre Sur", custom_fields: {})
    responsable = users(:pedro)
    ProjectResponsible.create!(
      project: assigned, responsible: responsable.responsible, responsible_type: responsible_types(:instalador)
    )

    assert_equal [assigned], Project.visible_to(responsable).to_a
  end

  test "visible_to a responsable with no linked Responsible returns none" do
    unlinked = User.create!(email: "sin-vinculo@example.com", password: "password123", role: "responsable")
    Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: {})

    assert_equal [], Project.visible_to(unlinked).to_a
  end
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `bin/rails test test/models/user_test.rb test/models/project_test.rb`
Expected: FAIL — `responsable` role/`responsible` association/`editable_project_stage_ids` don't exist yet.

- [ ] **Step 4: Update `User`**

In `app/models/user.rb`:

```ruby
  enum :role, { admin: "admin", gerente: "gerente", visor: "visor", responsable: "responsable" }, default: "visor"
```

Add next to `has_many :project_type_accesses, dependent: :destroy`:

```ruby
  has_one :responsible, dependent: :nullify
```

Replace `can_view_project?`:

```ruby
  def can_view_project?(project)
    return true if admin? || gerente?
    return project_accesses.exists?(project_id: project.id) if visor?
    return false if responsible.nil?
    ProjectResponsible.where(project_id: project.id, responsible_id: responsible.id).exists?
  end
```

Add this new method after `can_edit_project?`:

```ruby
  def editable_project_stage_ids(project)
    return project.project_stage_ids if admin? || can_edit_project?(project)
    return [] if responsible.nil?

    assignments = ProjectResponsible.where(project_id: project.id, responsible_id: responsible.id)
    return project.project_stage_ids if assignments.any?(&:project_wide?)
    assignments.filter_map(&:project_stage_id)
  end
```

- [ ] **Step 5: Update `Project.visible_to`**

In `app/models/project.rb`:

```ruby
  def self.visible_to(user)
    return all if user.admin? || user.gerente?
    return joins(:project_accesses).where(project_accesses: { user_id: user.id }) if user.visor?
    return none if user.responsible.nil?
    joins(:project_responsibles).where(project_responsibles: { responsible_id: user.responsible.id }).distinct
  end
```

- [ ] **Step 6: Add the role label**

In `app/helpers/application_helper.rb`:

```ruby
  ROLE_LABELS = { "admin" => "Administrador", "gerente" => "Gerente", "visor" => "Visor", "responsable" => "Responsable" }.freeze
  ROLE_BADGE_CLASSES = { "admin" => "bg-primary", "gerente" => "bg-info text-dark", "visor" => "bg-secondary", "responsable" => "bg-warning text-dark" }.freeze
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `bin/rails test test/models/user_test.rb test/models/project_test.rb`
Expected: PASS — note this run depends on `responsible_types(:instalador)` from Task 1's fixtures; if Task 1 isn't merged yet in your working copy, stop and confirm before continuing.

- [ ] **Step 8: Run the full suite**

Run: `bin/rails test`
Expected: PASS, no regressions (existing `can_view_project?`/`visible_to` behavior for admin/gerente/visor is unchanged, only the `responsable` branch is new).

- [ ] **Step 9: Commit**

```bash
git add app/models/user.rb app/models/project.rb app/helpers/application_helper.rb \
  test/models/user_test.rb test/models/project_test.rb test/fixtures/users.yml test/fixtures/responsibles.yml
git commit -m "Add responsable role with project/stage-scoped authorization"
```

---

### Task 3: Admin — catálogo de personas (`Admin::ResponsiblesController`)

**Files:**
- Create: `app/controllers/admin/responsibles_controller.rb`
- Create: `app/views/admin/responsibles/index.html.erb`
- Create: `app/views/admin/responsibles/_form.html.erb`
- Create: `app/views/admin/responsibles/new.html.erb`
- Create: `app/views/admin/responsibles/edit.html.erb`
- Modify: `config/routes.rb`
- Test: `test/controllers/admin/responsibles_controller_test.rb`

**Interfaces:**
- Consumes: `Responsible` (Task 1).
- Produces: `admin_responsibles_path`, `new_admin_responsible_path`, `edit_admin_responsible_path(responsible)`, `admin_responsible_path(responsible)`.

This controller/views are a straight copy of `Admin::InstallersController` and `app/views/admin/installers/*` (see those files for the exact pattern), with `Installer` → `Responsible`, plus an optional user-link select. It coexists with `Admin::InstallersController` until Task 8 removes the latter.

- [ ] **Step 1: Write the failing tests**

```ruby
# test/controllers/admin/responsibles_controller_test.rb
require "test_helper"

class Admin::ResponsiblesControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:juan) }

  test "index lists responsibles" do
    get admin_responsibles_path
    assert_response :success
    assert_select "body", /Ana Gómez/
  end

  test "create adds a new responsible" do
    assert_difference("Responsible.count", 1) do
      post admin_responsibles_path, params: { responsible: { name: "Nuevo Responsable" } }
    end
    assert_redirected_to admin_responsibles_path
  end

  test "create with blank name re-renders form with error" do
    assert_no_difference("Responsible.count") do
      post admin_responsibles_path, params: { responsible: { name: "" } }
    end
    assert_response :unprocessable_entity
  end

  test "create can link a user with no existing responsible" do
    unlinked_user = User.create!(email: "libre@example.com", password: "password123", role: "responsable")
    post admin_responsibles_path, params: { responsible: { name: "Nuevo", user_id: unlinked_user.id } }
    assert_equal unlinked_user, Responsible.order(:id).last.user
  end

  test "update changes the responsible's name and color" do
    responsible = responsibles(:ana_gomez)
    patch admin_responsible_path(responsible), params: { responsible: { name: "Ana G. Actualizada", color: "#f60404" } }
    assert_redirected_to admin_responsibles_path
    responsible.reload
    assert_equal "Ana G. Actualizada", responsible.name
    assert_equal "#f60404", responsible.color
  end

  test "destroy removes a responsible" do
    responsible = Responsible.create!(name: "Temporal")
    assert_difference("Responsible.count", -1) do
      delete admin_responsible_path(responsible)
    end
  end

  test "new and edit show the submit button in Spanish" do
    get new_admin_responsible_path
    assert_response :success
    assert_select "input[value=?]", "Crear Responsable"

    get edit_admin_responsible_path(responsibles(:ana_gomez))
    assert_response :success
    assert_select "input[value=?]", "Actualizar Responsable"
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/controllers/admin/responsibles_controller_test.rb`
Expected: FAIL — no route/controller yet.

- [ ] **Step 3: Add the route**

In `config/routes.rb`, inside `namespace :admin do`, add next to `resources :installers`:

```ruby
    resources :responsibles
```

- [ ] **Step 4: Create the controller**

```ruby
# app/controllers/admin/responsibles_controller.rb
class Admin::ResponsiblesController < Admin::BaseController
  before_action :set_responsible, only: [:edit, :update, :destroy]

  def index
    @responsibles = Responsible.all
  end

  def new
    @responsible = Responsible.new
  end

  def create
    @responsible = Responsible.new(responsible_params)
    if @responsible.save
      redirect_to admin_responsibles_path
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @responsible.update(responsible_params)
      redirect_to admin_responsibles_path
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @responsible.destroy
    redirect_to admin_responsibles_path
  end

  private

  def set_responsible
    @responsible = Responsible.find(params[:id])
  end

  def unlinked_users
    User.where(responsible: nil).or(User.where(id: @responsible&.user_id))
  end
  helper_method :unlinked_users

  def responsible_params
    params.require(:responsible).permit(:name, :color, :user_id)
  end
end
```

- [ ] **Step 5: Create the views**

```erb
<%# app/views/admin/responsibles/index.html.erb %>
<%= admin_card("Responsables") do %>
  <%= link_to "Nuevo responsable", new_admin_responsible_path, class: "btn btn-primary mb-3" %>
  <ul class="list-group">
    <% @responsibles.each do |responsible| %>
      <li class="list-group-item d-flex justify-content-between align-items-center">
        <span><span class="badge me-2" style="background-color: <%= responsible.color %>">&nbsp;</span><%= responsible.name %></span>
        <span>
          <%= link_to "Editar", edit_admin_responsible_path(responsible), class: "btn btn-outline-secondary btn-sm" %>
          <%= button_to "Borrar", admin_responsible_path(responsible), method: :delete,
                class: "btn btn-outline-danger btn-sm", form: { style: "display:inline-block", onsubmit: "return confirm('¿Eliminar responsable?')" } %>
        </span>
      </li>
    <% end %>
  </ul>
<% end %>
```

```erb
<%# app/views/admin/responsibles/_form.html.erb %>
<%= admin_card(responsible.persisted? ? "Editar responsable" : "Nuevo responsable") do %>
  <%= form_with model: [:admin, responsible] do |form| %>
    <% if responsible.errors.any? %>
      <div class="alert alert-danger">
        <ul class="mb-0">
          <% responsible.errors.full_messages.each do |message| %>
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

    <div class="mb-3">
      <%= form.label :user_id, "Usuario vinculado", class: "form-label" %>
      <%= form.collection_select :user_id, unlinked_users, :id, :email, { include_blank: "Ninguno" }, class: "form-select" %>
    </div>

    <%= form.submit class: "btn btn-primary" %>
  <% end %>
<% end %>
```

```erb
<%# app/views/admin/responsibles/new.html.erb %>
<%= render "form", responsible: @responsible %>
```

```erb
<%# app/views/admin/responsibles/edit.html.erb %>
<%= render "form", responsible: @responsible %>
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bin/rails test test/controllers/admin/responsibles_controller_test.rb`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add config/routes.rb app/controllers/admin/responsibles_controller.rb app/views/admin/responsibles \
  test/controllers/admin/responsibles_controller_test.rb
git commit -m "Add admin CRUD for the Responsible catalog"
```

---

### Task 4: Admin — tipos de responsable por tipo de proyecto

**Files:**
- Create: `app/controllers/admin/responsible_types_controller.rb`
- Create: `app/views/admin/responsible_types/_form.html.erb`
- Create: `app/views/admin/responsible_types/new.html.erb`
- Create: `app/views/admin/responsible_types/edit.html.erb`
- Modify: `config/routes.rb`
- Modify: `app/views/admin/project_types/show.html.erb`
- Test: `test/controllers/admin/responsible_types_controller_test.rb`

**Interfaces:**
- Consumes: `ResponsibleType` (Task 1), `ProjectType#responsible_types` (already available via `has_many` — no, `ProjectType` needs this association added here since Task 1 only added it on the `ResponsibleType` side as `belongs_to`).
- Produces: `admin_project_type_responsible_types_path(project_type)`, `admin_project_type_responsible_type_path(project_type, responsible_type)`.

Follows the exact same pattern as `Admin::LogEntryTypesController` (flat controller name, nested under `project_type`, no reorder — this codebase's convention for `log_entry_types` is a flat `Admin::LogEntryTypesController`, not a namespaced `Admin::ProjectTypes::LogEntryTypesController`; `responsible_types` follows the same flat convention for consistency).

- [ ] **Step 1: Add `ProjectType#responsible_types`**

In `app/models/project_type.rb`, add next to `has_many :log_entry_types, dependent: :destroy`:

```ruby
  has_many :responsible_types, dependent: :destroy
```

- [ ] **Step 2: Write the failing tests**

```ruby
# test/controllers/admin/responsible_types_controller_test.rb
require "test_helper"

class Admin::ResponsibleTypesControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:juan) }
  setup { @project_type = project_types(:instalaciones) }

  test "create adds a responsible_type to the project type" do
    assert_difference("@project_type.responsible_types.count", 1) do
      post admin_project_type_responsible_types_path(@project_type), params: {
        responsible_type: { name: "Electricista" }
      }
    end
    assert_redirected_to admin_project_type_path(@project_type)
  end

  test "create with blank name re-renders form with error" do
    assert_no_difference("@project_type.responsible_types.count") do
      post admin_project_type_responsible_types_path(@project_type), params: {
        responsible_type: { name: "" }
      }
    end
    assert_response :unprocessable_entity
  end

  test "update saves the name" do
    type = responsible_types(:disenador)
    patch admin_project_type_responsible_type_path(@project_type, type), params: {
      responsible_type: { name: "Diseñador Senior" }
    }
    assert_redirected_to admin_project_type_path(@project_type)
    assert_equal "Diseñador Senior", type.reload.name
  end

  test "destroy removes a responsible_type" do
    type = responsible_types(:disenador)
    assert_difference("@project_type.responsible_types.count", -1) do
      delete admin_project_type_responsible_type_path(@project_type, type)
    end
  end

  test "destroy cascades to its project_responsibles" do
    project = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: {})
    responsible = responsibles(:ana_gomez)
    type = responsible_types(:disenador)
    ProjectResponsible.create!(project: project, responsible: responsible, responsible_type: type)

    assert_difference("ProjectResponsible.count", -1) do
      delete admin_project_type_responsible_type_path(@project_type, type)
    end
  end
end
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `bin/rails test test/controllers/admin/responsible_types_controller_test.rb`
Expected: FAIL — no route/controller yet.

- [ ] **Step 4: Add the route**

In `config/routes.rb`, inside `resources :project_types do`, add next to `resources :log_entry_types, except: [:index, :show]`:

```ruby
      resources :responsible_types, except: [:index, :show]
```

- [ ] **Step 5: Create the controller**

```ruby
# app/controllers/admin/responsible_types_controller.rb
class Admin::ResponsibleTypesController < Admin::BaseController
  before_action :set_project_type
  before_action :set_responsible_type, only: [:edit, :update, :destroy]

  def new
    @responsible_type = @project_type.responsible_types.new
  end

  def create
    @responsible_type = @project_type.responsible_types.new(responsible_type_params)
    if @responsible_type.save
      redirect_to admin_project_type_path(@project_type)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @responsible_type.update(responsible_type_params)
      redirect_to admin_project_type_path(@project_type)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @responsible_type.destroy
    redirect_to admin_project_type_path(@project_type)
  end

  private

  def set_project_type
    @project_type = ProjectType.find(params[:project_type_id])
  end

  def set_responsible_type
    @responsible_type = @project_type.responsible_types.find(params[:id])
  end

  def responsible_type_params
    params.require(:responsible_type).permit(:name)
  end
end
```

- [ ] **Step 6: Create the views**

```erb
<%# app/views/admin/responsible_types/_form.html.erb %>
<%= admin_card(@responsible_type.persisted? ? "Editar tipo de responsable" : "Nuevo tipo de responsable") do %>
  <%= form_with model: [@project_type, @responsible_type], url: @responsible_type.persisted? ? admin_project_type_responsible_type_path(@project_type, @responsible_type) : admin_project_type_responsible_types_path(@project_type) do |f| %>
    <div class="mb-3">
      <%= f.label :name, "Nombre" %>
      <%= f.text_field :name, class: "form-control" %>
    </div>
    <%= f.submit (@responsible_type.persisted? ? "Actualizar Tipo de Responsable" : "Crear Tipo de Responsable"), class: "btn btn-primary" %>
  <% end %>
<% end %>
```

```erb
<%# app/views/admin/responsible_types/new.html.erb %>
<%= render "form" %>
```

```erb
<%# app/views/admin/responsible_types/edit.html.erb %>
<%= render "form" %>
```

- [ ] **Step 7: Add the card to `admin/project_types/show.html.erb`**

Add this card after the "Tipos de Bitácora" card (before the closing `<script>` block):

```erb
<div class="card mb-4">
  <div class="card-header">Tipos de responsable</div>
  <div class="card-body">
    <%= link_to "Nuevo tipo", new_admin_project_type_responsible_type_path(@project_type), class: "btn btn-primary btn-sm mb-2" %>
    <ul class="list-group list-group-flush">
      <% @project_type.responsible_types.order(:name).each do |type| %>
        <li class="list-group-item d-flex justify-content-between align-items-center">
          <span><%= type.name %></span>
          <span>
            <%= link_to "Editar", edit_admin_project_type_responsible_type_path(@project_type, type), class: "btn btn-outline-secondary btn-sm" %>
            <%= button_to "Eliminar", admin_project_type_responsible_type_path(@project_type, type), method: :delete,
                  class: "btn btn-outline-danger btn-sm", form: { style: "display:inline-block", onsubmit: "return confirm('¿Eliminar tipo de responsable?')" } %>
          </span>
        </li>
      <% end %>
    </ul>
  </div>
</div>
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `bin/rails test test/controllers/admin/responsible_types_controller_test.rb`
Expected: PASS

- [ ] **Step 9: Run the full suite**

Run: `bin/rails test`
Expected: PASS

- [ ] **Step 10: Commit**

```bash
git add app/models/project_type.rb config/routes.rb app/controllers/admin/responsible_types_controller.rb \
  app/views/admin/responsible_types app/views/admin/project_types/show.html.erb \
  test/controllers/admin/responsible_types_controller_test.rb
git commit -m "Add admin CRUD for responsible types per project type"
```

---

### Task 5: Asignar responsables en el proyecto

**Files:**
- Create: `app/controllers/project_responsibles_controller.rb`
- Modify: `config/routes.rb`
- Modify: `app/views/projects/show.html.erb`
- Test: `test/controllers/project_responsibles_controller_test.rb`

**Interfaces:**
- Consumes: `ProjectResponsible`, `Responsible`, `ResponsibleType` (Task 1), `User#can_edit_project?` (existing, unchanged).
- Produces: `project_project_responsibles_path(project)`, `project_project_responsible_path(project, project_responsible)`.

- [ ] **Step 1: Write the failing tests**

```ruby
# test/controllers/project_responsibles_controller_test.rb
require "test_helper"

class ProjectResponsiblesControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:juan) }
  setup do
    @project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
  end

  test "create adds a project-wide assignment" do
    assert_difference("@project.project_responsibles.count", 1) do
      post project_project_responsibles_path(@project), params: {
        project_responsible: { responsible_id: responsibles(:ana_gomez).id, responsible_type_id: responsible_types(:instalador).id }
      }
    end
    assert_redirected_to project_path(@project)
    assert @project.project_responsibles.last.project_wide?
  end

  test "create adds a stage-scoped assignment" do
    stage = @project.project_stages.first
    post project_project_responsibles_path(@project), params: {
      project_responsible: {
        responsible_id: responsibles(:ana_gomez).id, responsible_type_id: responsible_types(:instalador).id,
        project_stage_id: stage.id
      }
    }
    assert_equal stage, @project.project_responsibles.last.project_stage
  end

  test "create with an invalid combination re-renders the project with an error" do
    ProjectResponsible.create!(project: @project, responsible: responsibles(:ana_gomez), responsible_type: responsible_types(:instalador))
    assert_no_difference("@project.project_responsibles.count") do
      post project_project_responsibles_path(@project), params: {
        project_responsible: { responsible_id: responsibles(:ana_gomez).id, responsible_type_id: responsible_types(:instalador).id }
      }
    end
    assert_redirected_to project_path(@project)
  end

  test "destroy removes an assignment" do
    pr = ProjectResponsible.create!(project: @project, responsible: responsibles(:ana_gomez), responsible_type: responsible_types(:instalador))
    assert_difference("@project.project_responsibles.count", -1) do
      delete project_project_responsible_path(@project, pr)
    end
  end

  test "visor without edit access cannot create an assignment" do
    sign_in users(:maria)
    assert_no_difference("@project.project_responsibles.count") do
      post project_project_responsibles_path(@project), params: {
        project_responsible: { responsible_id: responsibles(:ana_gomez).id, responsible_type_id: responsible_types(:instalador).id }
      }
    end
    assert_redirected_to root_path
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/controllers/project_responsibles_controller_test.rb`
Expected: FAIL — no route/controller yet.

- [ ] **Step 3: Add the route**

In `config/routes.rb`, inside `resources :projects do`, add next to `resources :log_entries, only: [:create, :destroy]`:

```ruby
    resources :project_responsibles, only: [:create, :destroy]
```

- [ ] **Step 4: Create the controller**

```ruby
# app/controllers/project_responsibles_controller.rb
class ProjectResponsiblesController < ApplicationController
  before_action :set_project
  before_action :authorize_edit!

  def create
    @project_responsible = @project.project_responsibles.new(project_responsible_params)
    if @project_responsible.save
      redirect_to project_path(@project)
    else
      redirect_to project_path(@project), alert: @project_responsible.errors.full_messages.to_sentence
    end
  end

  def destroy
    @project.project_responsibles.find(params[:id]).destroy
    redirect_to project_path(@project)
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end

  def authorize_edit!
    return if current_user.can_edit_project?(@project)
    redirect_to root_path, alert: "No tenés permiso para hacer eso."
  end

  def project_responsible_params
    params.require(:project_responsible).permit(:responsible_id, :responsible_type_id, :project_stage_id)
  end
end
```

- [ ] **Step 5: Add the card to `projects/show.html.erb`**

Add this card right after the "Cronograma" card (before "Bitácora"):

```erb
<% if current_user.can_edit_project?(@project) %>
  <div class="card mb-4">
    <div class="card-header">Responsables</div>
    <div class="card-body">
      <ul class="list-group list-group-flush mb-3">
        <% @project.project_responsibles.includes(:responsible, :responsible_type, :project_stage).each do |pr| %>
          <li class="list-group-item d-flex justify-content-between align-items-center">
            <span>
              <span class="badge me-2" style="background-color: <%= pr.responsible.color %>">&nbsp;</span>
              <%= pr.responsible.name %> — <%= pr.responsible_type.name %>
              (<%= pr.project_stage&.name || "Todo el proyecto" %>)
            </span>
            <%= button_to "Quitar", project_project_responsible_path(@project, pr), method: :delete,
                  class: "btn btn-outline-danger btn-sm", form: { style: "display:inline-block", onsubmit: "return confirm('¿Quitar responsable?')" } %>
          </li>
        <% end %>
      </ul>
      <%= form_with model: ProjectResponsible.new, url: project_project_responsibles_path(@project) do |form| %>
        <div class="row g-2">
          <div class="col-auto">
            <%= form.collection_select :responsible_id, Responsible.order(:name), :id, :name, { include_blank: "Responsable" }, class: "form-select" %>
          </div>
          <div class="col-auto">
            <%= form.collection_select :responsible_type_id, @project.project_type.responsible_types.order(:name), :id, :name, { include_blank: "Tipo" }, class: "form-select" %>
          </div>
          <div class="col-auto">
            <%= form.collection_select :project_stage_id, @project.project_stages, :id, :name, { include_blank: "Todo el proyecto" }, class: "form-select" %>
          </div>
          <div class="col-auto">
            <%= form.submit "Agregar", class: "btn btn-primary" %>
          </div>
        </div>
      <% end %>
    </div>
  </div>
<% end %>
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bin/rails test test/controllers/project_responsibles_controller_test.rb`
Expected: PASS

- [ ] **Step 7: Run the full suite**

Run: `bin/rails test`
Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add config/routes.rb app/controllers/project_responsibles_controller.rb app/views/projects/show.html.erb \
  test/controllers/project_responsibles_controller_test.rb
git commit -m "Let admin/gerente assign responsables to a project or a specific stage"
```

---

### Task 6: Edición de avance restringida para el rol `responsable`

**Files:**
- Modify: `app/controllers/projects_controller.rb`
- Create: `app/views/projects/_stage_table_restricted.html.erb`
- Modify: `app/views/projects/show.html.erb`
- Test: `test/controllers/projects_controller_test.rb`

**Interfaces:**
- Consumes: `User#editable_project_stage_ids` (Task 2).
- Produces: `ProjectsController#authorize_update!` (new, replaces `authorize_edit!` on the `update` action only), `_stage_table_restricted` partial.

The real stage-editing surface is `projects/show.html.erb`'s `_stage_table` partial and its interactive Gantt, both of which PATCH to `ProjectsController#update` — **not** the `edit`/`_form` page (that page only ever edits `name` + `custom_fields`). This task keeps `edit`/`_form` exactly as-is (still admin/gerente-only) and instead makes `update` accept a second, narrower kind of request: a `responsable`-role user submitting only `progress_percent` for their assigned stages.

- [ ] **Step 1: Write the failing tests**

Add to `test/controllers/projects_controller_test.rb` (find the existing `class ProjectsControllerTest` and add inside it):

```ruby
  test "responsable can update progress_percent on an assigned stage via the project PATCH" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    stage = project.project_stages.first
    responsable = users(:pedro)
    ProjectResponsible.create!(project: project, responsible: responsable.responsible, responsible_type: responsible_types(:instalador), project_stage: stage)
    sign_in responsable

    patch project_path(project), params: {
      project: { project_stages_attributes: { "0" => { id: stage.id, progress_percent: 55 } } }
    }

    assert_redirected_to project_path(project)
    assert_equal 55, stage.reload.progress_percent
  end

  test "responsable cannot update a stage they are not assigned to" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    stages = project.project_stages.order(:id).to_a
    assigned_stage, other_stage = stages[0], stages[1]
    responsable = users(:pedro)
    ProjectResponsible.create!(project: project, responsible: responsable.responsible, responsible_type: responsible_types(:instalador), project_stage: assigned_stage)
    sign_in responsable

    patch project_path(project), params: {
      project: { project_stages_attributes: { "0" => { id: other_stage.id, progress_percent: 90 } } }
    }

    assert_equal 0, other_stage.reload.progress_percent
  end

  test "responsable cannot change the project name via the project PATCH" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    stage = project.project_stages.first
    responsable = users(:pedro)
    ProjectResponsible.create!(project: project, responsible: responsable.responsible, responsible_type: responsible_types(:instalador), project_stage: stage)
    sign_in responsable

    patch project_path(project), params: {
      project: { name: "Nombre Hackeado", project_stages_attributes: { "0" => { id: stage.id, progress_percent: 10 } } }
    }

    assert_equal "Torre Norte", project.reload.name
  end

  test "responsable with no assignment on the project cannot PATCH it at all" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    sign_in users(:pedro)

    patch project_path(project), params: { project: { name: "Nombre Hackeado" } }

    assert_redirected_to projects_path
    assert_equal "Torre Norte", project.reload.name
  end

  test "responsable with a project-wide assignment sees an editable row for every stage on show" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    responsable = users(:pedro)
    ProjectResponsible.create!(project: project, responsible: responsable.responsible, responsible_type: responsible_types(:instalador))
    sign_in responsable

    get project_path(project)
    assert_response :success
    project.project_stages.each do |stage|
      assert_select "input[name=?]", "project[project_stages_attributes][#{stage.id}][progress_percent]"
    end
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n "/responsable/"`
Expected: FAIL — `update` currently rejects a `responsable`-role user outright (redirected by the existing `authorize_edit!`), and the restricted stage table doesn't exist.

- [ ] **Step 3: Split the authorization before_action**

In `app/controllers/projects_controller.rb`, replace:

```ruby
  before_action :authorize_edit!, only: [:edit, :update]
```

with:

```ruby
  before_action :authorize_edit!, only: [:edit]
  before_action :authorize_update!, only: [:update]
```

Add this new private method next to `authorize_edit!`:

```ruby
  def authorize_update!
    return if current_user.can_edit_project?(@project) || current_user.editable_project_stage_ids(@project).any?
    redirect_to projects_path, alert: "No tenés permiso para editar ese proyecto."
  end
```

- [ ] **Step 4: Branch `update` on full vs. restricted access**

Replace the `update` action:

```ruby
  def update
    @project_type = @project.project_type
    success =
      if current_user.can_edit_project?(@project)
        @project.update(project_params)
      else
        update_progress_only!
      end

    respond_to do |format|
      format.html do
        if success
          redirect_to project_path(@project)
        else
          render :edit, status: :unprocessable_entity
        end
      end
      format.json do
        if success
          render json: stage_payload
        else
          render json: { errors: @project.errors.full_messages }, status: :unprocessable_entity
        end
      end
    end
  end
```

Add this new private method next to `stage_payload`:

```ruby
  def update_progress_only!
    editable_ids = current_user.editable_project_stage_ids(@project).map(&:to_s)
    submitted = params.fetch(:project, {})[:project_stages_attributes] || {}
    submitted.each_value do |attrs|
      next unless editable_ids.include?(attrs["id"].to_s)
      next if attrs["progress_percent"].blank?
      @project.project_stages.find(attrs["id"]).update(progress_percent: attrs["progress_percent"])
    end
    true
  end
```

- [ ] **Step 5: Add the restricted stage table partial**

```erb
<%# app/views/projects/_stage_table_restricted.html.erb %>
<%= form_with model: project do |f| %>
  <table class="table table-sm table-bordered mb-0 stage-table">
    <thead>
      <tr><th>Etapa</th><th>% Avance</th><th>Estado</th></tr>
    </thead>
    <tbody>
      <% project.project_stages.includes(:stage_template).order(:id).each do |stage| %>
        <tr>
          <td><%= stage.name %></td>
          <td>
            <% if editable_stage_ids.include?(stage.id) %>
              <%= hidden_field_tag "project[project_stages_attributes][#{stage.id}][id]", stage.id %>
              <%= number_field_tag "project[project_stages_attributes][#{stage.id}][progress_percent]", stage.progress_percent,
                    min: 0, max: 100, class: "form-control form-control-sm" %>
            <% else %>
              <%= stage.progress_percent %>%
            <% end %>
          </td>
          <td>
            <%= progress_status_badge(stage.progress_status) %>
            <%= overdue_badge if stage.overdue? %>
          </td>
        </tr>
      <% end %>
    </tbody>
  </table>
  <%= f.submit "Guardar avance", class: "btn btn-primary btn-sm mt-3" %>
<% end %>
```

- [ ] **Step 6: Branch on which stage table to render in `show.html.erb`**

Replace:

```erb
    <% if current_user.can_edit_project?(@project) %>
      <%= render "stage_table", project: @project %>
    <% end %>
```

with:

```erb
    <% if current_user.can_edit_project?(@project) %>
      <%= render "stage_table", project: @project %>
    <% elsif current_user.editable_project_stage_ids(@project).any? %>
      <%= render "stage_table_restricted", project: @project, editable_stage_ids: current_user.editable_project_stage_ids(@project) %>
    <% end %>
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: PASS

- [ ] **Step 8: Run the full suite**

Run: `bin/rails test`
Expected: PASS

- [ ] **Step 9: Commit**

```bash
git add app/controllers/projects_controller.rb app/views/projects/_stage_table_restricted.html.erb \
  app/views/projects/show.html.erb test/controllers/projects_controller_test.rb
git commit -m "Let a responsable edit progress_percent on their assigned stages only"
```

---

### Task 7: Adaptar filtro, color del Gantt y asignación masiva

**Files:**
- Modify: `app/controllers/projects_controller.rb`
- Modify: `app/views/projects/_project_type_section.html.erb`
- Modify: `app/views/projects/tracker.html.erb`
- Modify: `config/routes.rb`
- Test: `test/controllers/projects_controller_test.rb`

**Interfaces:**
- Consumes: `ProjectResponsible`, `Responsible`, `ResponsibleType`, `Project#responsible_for` (Task 1).
- Produces: `filter_by_responsible`/`filter_by_no_responsible` (replace `filter_by_installer`/`filter_by_no_installer`), `bulk_assign_responsible` action (replaces `bulk_assign_installer`), `bulk_assign_responsible_projects_path`.

This task fully replaces the installer-filter/color/bulk-assign code path with the `Responsible`/`ResponsibleType` equivalent — `Installer`/`FieldDefinition.reference_table: "installers"` stop being referenced anywhere in `ProjectsController` or its views after this task. `Installer` itself (model, admin controller/views, table) is only removed in Task 8, once nothing points at it anymore.

- [ ] **Step 1: Write the failing tests**

Replace every existing test in `test/controllers/projects_controller_test.rb` that references `installer_id`/`bulk_assign_installer`/`Installer` (search for `installer` case-insensitively) with these equivalents — same behavior, new params:

```ruby
  test "index filters by responsible" do
    slug = project_types(:instalaciones).slug
    con_ana = Project.create!(project_type: project_types(:instalaciones), name: "Con Ana", custom_fields: {})
    ProjectResponsible.create!(project: con_ana, responsible: responsibles(:ana_gomez), responsible_type: responsible_types(:instalador))
    otro_responsable = Responsible.create!(name: "Otro")
    con_otro = Project.create!(project_type: project_types(:instalaciones), name: "Con Otro", custom_fields: {})
    ProjectResponsible.create!(project: con_otro, responsible: otro_responsable, responsible_type: responsible_types(:instalador))

    get projects_path, params: {
      sections: { slug => { responsible_type_id: responsible_types(:instalador).id, responsible_id: responsibles(:ana_gomez).id } }
    }
    assert_response :success
    assert_match(/#{con_ana.name}/, response.body)
    assert_no_match(/#{con_otro.name}/, response.body)
  end

  test "index filters by Sin asignar for a chosen type" do
    slug = project_types(:instalaciones).slug
    sin_asignar = Project.create!(project_type: project_types(:instalaciones), name: "Sin Asignar", custom_fields: {})
    con_asignacion = Project.create!(project_type: project_types(:instalaciones), name: "Con Asignación", custom_fields: {})
    ProjectResponsible.create!(project: con_asignacion, responsible: responsibles(:ana_gomez), responsible_type: responsible_types(:instalador))

    get projects_path, params: {
      sections: { slug => { responsible_type_id: responsible_types(:instalador).id, responsible_id: "none" } }
    }
    assert_response :success
    assert_match(/#{sin_asignar.name}/, response.body)
    assert_no_match(/#{con_asignacion.name}/, response.body)
  end

  test "index shows a Tipo de responsable and Responsable filter" do
    get projects_path
    assert_response :success
    slug = project_types(:instalaciones).slug
    assert_select "select#sections_#{slug}_responsible_type_id"
    assert_select "select#sections_#{slug}_responsible_id"
  end

  test "tracker filters by responsible" do
    con_ana = Project.create!(project_type: project_types(:instalaciones), name: "Con Ana", custom_fields: {})
    ProjectResponsible.create!(project: con_ana, responsible: responsibles(:ana_gomez), responsible_type: responsible_types(:instalador))
    otro_responsable = Responsible.create!(name: "Otro")
    con_otro = Project.create!(project_type: project_types(:instalaciones), name: "Con Otro", custom_fields: {})
    ProjectResponsible.create!(project: con_otro, responsible: otro_responsable, responsible_type: responsible_types(:instalador))

    get tracker_projects_path, params: { responsible_type_id: responsible_types(:instalador).id, responsible_id: responsibles(:ana_gomez).id }
    assert_response :success
    assert_match(/#{con_ana.name}/, response.body)
    assert_no_match(/#{con_otro.name}/, response.body)
  end

  test "bulk_assign_responsible assigns the responsible to every selected project at the project level" do
    proyecto_a = Project.create!(project_type: project_types(:instalaciones), name: "Proyecto A", custom_fields: {})
    proyecto_b = Project.create!(project_type: project_types(:instalaciones), name: "Proyecto B", custom_fields: {})

    patch bulk_assign_responsible_projects_path, params: {
      responsible_type_id: responsible_types(:instalador).id, responsible_id: responsibles(:ana_gomez).id,
      project_ids: [proyecto_a.id, proyecto_b.id]
    }

    assert_redirected_to projects_path
    assert proyecto_a.reload.project_responsibles.exists?(responsible: responsibles(:ana_gomez), responsible_type: responsible_types(:instalador))
    assert proyecto_b.reload.project_responsibles.exists?(responsible: responsibles(:ana_gomez), responsible_type: responsible_types(:instalador))
    follow_redirect!
    assert_match(/Responsable asignado a 2 proyecto\(s\)/, response.body)
  end

  test "bulk_assign_responsible replaces an existing project-wide assignment of the same type" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Proyecto A", custom_fields: {})
    ProjectResponsible.create!(project: project, responsible: responsibles(:ana_gomez), responsible_type: responsible_types(:instalador))
    otro_responsable = Responsible.create!(name: "Otro")

    patch bulk_assign_responsible_projects_path, params: {
      responsible_type_id: responsible_types(:instalador).id, responsible_id: otro_responsable.id, project_ids: [project.id]
    }

    assert_equal [otro_responsable], project.reload.project_responsibles.where(responsible_type: responsible_types(:instalador), project_stage: nil).map(&:responsible)
  end

  test "bulk_assign_responsible without a type or responsible chosen does nothing and redirects with an alert" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Proyecto A", custom_fields: {})

    patch bulk_assign_responsible_projects_path, params: { responsible_type_id: "", responsible_id: "", project_ids: [project.id] }

    assert_redirected_to projects_path
    assert_equal [], project.reload.project_responsibles.to_a
    follow_redirect!
    assert_match(/Elegí un tipo, un responsable y al menos un proyecto/, response.body)
  end
```

Delete the old installer-based tests you're replacing (search the file for `installer` case-insensitively — every match is either a test being replaced above or setup data for a test being replaced; there is no installer-related test left in this file once this task is done, since Task 8 removes `Installer` entirely).

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n "/responsible|Responsable/"`
Expected: FAIL — routes/params don't exist yet.

- [ ] **Step 3: Update the route**

In `config/routes.rb`, replace:

```ruby
  patch "projects/bulk_assign_installer", to: "projects#bulk_assign_installer", as: :bulk_assign_installer_projects
```

with:

```ruby
  patch "projects/bulk_assign_responsible", to: "projects#bulk_assign_responsible", as: :bulk_assign_responsible_projects
```

- [ ] **Step 4: Update `ProjectsController`**

Replace `before_action :require_admin_or_gerente!, only: [:new, :create, :bulk_assign_installer]` with:

```ruby
  before_action :require_admin_or_gerente!, only: [:new, :create, :bulk_assign_responsible]
```

Replace the `@installers = Installer.all` line in `index` and in `tracker` with `@responsible_types = ResponsibleType.all` — actually each section/tracker filters within a single `project_type`, so scope it: in `index`, remove `@installers = Installer.all` entirely (each section already has `section[:project_type]`, from which the view reaches `.responsible_types`); in `tracker`, replace `@installers = Installer.all` with `@responsible_types = @project_type ? @project_type.responsible_types : ResponsibleType.none`, computed **after** `@project_type` is assigned (move the line down).

Replace `tracker`'s filter line:

```ruby
      params[:installer_id].present? ? filter_by_installer(scope, params[:installer_id]) : scope
```

with:

```ruby
      filter_by_responsible(scope, params[:responsible_type_id], params[:responsible_id])
```

Replace `bulk_assign_installer` entirely:

```ruby
  def bulk_assign_responsible
    project_ids = Array(params[:project_ids]).reject(&:blank?)
    if params[:responsible_type_id].blank? || params[:responsible_id].blank? || project_ids.empty?
      redirect_to projects_path(request.query_parameters), alert: "Elegí un tipo, un responsable y al menos un proyecto." and return
    end

    editable_projects = Project.visible_to(current_user).where(id: project_ids).select { |project| current_user.can_edit_project?(project) }
    count = 0
    editable_projects.each do |project|
      existing = project.project_responsibles.find_by(responsible_type_id: params[:responsible_type_id], project_stage_id: nil)
      existing&.destroy
      project.project_responsibles.create!(responsible_type_id: params[:responsible_type_id], responsible_id: params[:responsible_id])
      count += 1
    end

    redirect_to projects_path(request.query_parameters), notice: "Responsable asignado a #{count} proyecto(s)."
  end
```

Replace `filter_by_installer`/`filter_by_no_installer` with:

```ruby
  def filter_by_responsible(scope, responsible_type_id, responsible_id)
    return scope if responsible_type_id.blank?
    matching = ProjectResponsible.where(responsible_type_id: responsible_type_id)
    if responsible_id.blank?
      scope
    elsif responsible_id == "none"
      scope.where.not(id: matching.select(:project_id))
    else
      scope.where(id: matching.where(responsible_id: responsible_id).select(:project_id))
    end
  end
```

In `build_section`, replace:

```ruby
    if section_params[:installer_id] == "none"
      projects = filter_by_no_installer(projects)
    elsif section_params[:installer_id].present?
      projects = filter_by_installer(projects, section_params[:installer_id])
    end
```

with:

```ruby
    projects = filter_by_responsible(projects, section_params[:responsible_type_id], section_params[:responsible_id])
```

- [ ] **Step 5: Update `_project_type_section.html.erb`**

Replace the "Instalador" filter field:

```erb
      <div class="col-auto">
        <%= form.label :installer_id, "Instalador", class: "form-label" %>
        <%= form.select :installer_id,
              [["Sin instalador", "none"]] + @installers.collect { |i| [i.name, i.id] },
              { include_blank: "Todos", selected: section_params[:installer_id] }, class: "form-select" %>
      </div>
```

with two chained fields:

```erb
      <div class="col-auto">
        <%= form.label :responsible_type_id, "Tipo de responsable", class: "form-label" %>
        <%= form.select :responsible_type_id, project_type.responsible_types.order(:name).collect { |t| [t.name, t.id] },
              { include_blank: "Todos", selected: section_params[:responsible_type_id] }, class: "form-select" %>
      </div>
      <div class="col-auto">
        <%= form.label :responsible_id, "Responsable", class: "form-label" %>
        <%= form.select :responsible_id,
              [["Sin asignar", "none"]] + Responsible.joins(:project_responsibles).where(project_responsibles: { responsible_type_id: section_params[:responsible_type_id] }).distinct.order(:name).collect { |r| [r.name, r.id] },
              { include_blank: "Todos", selected: section_params[:responsible_id] }, class: "form-select" %>
      </div>
```

Update the "Quitar filtros" link's blanked keys — replace `"installer_id" => ""` with `"responsible_type_id" => "", "responsible_id" => ""`.

Replace the Gantt task/color computation:

```erb
  <%
    gantt_tasks = projects_list.filter_map do |project|
      if section[:stage_name].present?
        stage = project.project_stages.find { |s| s.name == section[:stage_name] }
        next if stage.nil?
        stage_start = stage.start_date || project.created_at.to_date
        stage_end = stage.end_date || (stage_start + 7.days)
        first, last = stage_start, stage_end
      else
        first, last = project.gantt_window
      end
      progress_values = project.project_stages.map(&:progress_percent)
      average_progress = progress_values.any? ? (progress_values.sum / progress_values.size.to_f).round : 0
      selected_type = ResponsibleType.find_by(id: section_params[:responsible_type_id])
      responsible = selected_type ? project.responsible_for(selected_type) : nil
      {
        id: project.id.to_s,
        name: project.name,
        start: first.to_s,
        end: last.to_s,
        progress: average_progress,
        edit_url: project_path(project),
        custom_class: "responsible-color-#{responsible&.id || 'none'}"
      }
    end
    selected_type = ResponsibleType.find_by(id: section_params[:responsible_type_id])
    gantt_colors = if selected_type
      projects_list.map { |project| project.responsible_for(selected_type) }.compact.uniq.map { |r| [r.id, r.color] }
    else
      []
    end
  %>
```

And the corresponding style block key from `installer-color-` to `responsible-color-`:

```erb
        <% gantt_colors.each do |responsible_id, color| %>
          .gantt .bar-wrapper.responsible-color-<%= responsible_id %> .bar,
          .gantt .bar-wrapper.responsible-color-<%= responsible_id %>:hover .bar,
          .gantt .bar-wrapper.responsible-color-<%= responsible_id %>.active .bar {
            fill: <%= color %>;
          }
        <% end %>
```

Replace the bulk-assign form:

```erb
  <% if current_user.admin? || current_user.gerente? %>
    <%= form_with url: bulk_assign_responsible_projects_path(request.query_parameters), method: :patch, local: true,
          id: "bulk-assign-form-#{slug}", class: "d-flex gap-2 align-items-end mb-3" do |f| %>
      <div>
        <%= f.label :responsible_type_id, "Tipo", for: "bulk-assign-type-select-#{slug}", class: "form-label" %>
        <%= f.select :responsible_type_id, project_type.responsible_types.order(:name).collect { |t| [t.name, t.id] },
              { include_blank: "Elegí un tipo", selected: section_params[:responsible_type_id] }, class: "form-select", id: "bulk-assign-type-select-#{slug}" %>
      </div>
      <div>
        <%= f.label :responsible_id, "Asignar a los seleccionados", for: "bulk-assign-responsible-select-#{slug}", class: "form-label" %>
        <%= f.select :responsible_id, Responsible.order(:name).collect { |r| [r.name, r.id] },
              { include_blank: "Elegí un responsable" }, class: "form-select", id: "bulk-assign-responsible-select-#{slug}" %>
      </div>
      <%= f.submit "Asignar", class: "btn btn-primary" %>
    <% end %>
  <% end %>
```

- [ ] **Step 6: Update `tracker.html.erb`**

Replace the "Instalador" filter field:

```erb
  <div class="col-auto">
    <%= form.label :installer_id, "Instalador", class: "form-label" %>
    <%= form.select :installer_id, @installers.collect { |i| [i.name, i.id] },
          { include_blank: "Todos", selected: params[:installer_id] }, class: "form-select" %>
  </div>
```

with:

```erb
  <div class="col-auto">
    <%= form.label :responsible_type_id, "Tipo de responsable", class: "form-label" %>
    <%= form.select :responsible_type_id, @responsible_types.collect { |t| [t.name, t.id] },
          { include_blank: "Todos", selected: params[:responsible_type_id] }, class: "form-select" %>
  </div>
  <div class="col-auto">
    <%= form.label :responsible_id, "Responsable", class: "form-label" %>
    <%= form.select :responsible_id,
          [["Sin asignar", "none"]] + Responsible.joins(:project_responsibles).where(project_responsibles: { responsible_type_id: params[:responsible_type_id] }).distinct.collect { |r| [r.name, r.id] },
          { include_blank: "Todos", selected: params[:responsible_id] }, class: "form-select" %>
  </div>
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: PASS

- [ ] **Step 8: Run the full suite**

Run: `bin/rails test`
Expected: PASS — `Installer` still exists and is untouched by this task (Task 8 removes it), so any remaining `Admin::InstallersController`/`Installer` model tests still pass unchanged.

- [ ] **Step 9: Commit**

```bash
git add app/controllers/projects_controller.rb app/views/projects/_project_type_section.html.erb \
  app/views/projects/tracker.html.erb config/routes.rb test/controllers/projects_controller_test.rb
git commit -m "Adapt project filter, Gantt coloring, and bulk-assign to Responsible/ResponsibleType"
```

---

### Task 8: Migrar datos de `Installer` y eliminarlo

**Files:**
- Create: `db/migrate/<timestamp>_migrate_installers_to_responsibles.rb`
- Create: `db/migrate/<timestamp>_drop_installers.rb`
- Delete: `app/models/installer.rb`
- Delete: `app/controllers/admin/installers_controller.rb`
- Delete: `app/views/admin/installers/` (all 4 files)
- Delete: `test/models/installer_test.rb`
- Delete: `test/controllers/admin/installers_controller_test.rb`
- Delete: `test/fixtures/installers.yml`
- Modify: `config/routes.rb`
- Modify: `config/locales/es.yml`
- Modify: `test/fixtures/field_definitions.yml`
- Modify: `test/models/project_test.rb`
- Test: `test/integration/migrate_installers_to_responsibles_test.rb` (new)

**Interfaces:**
- Consumes: everything from Tasks 1–7. This task removes the last references to `Installer`, `FieldDefinition.reference_table: "installers"`, and `Project#installer`.

`Installer` and the `installers` table cease to exist in the codebase and schema right after this task's migrations run, so there is no way to write a Minitest that exercises `MigrateInstallersToResponsibles#up` against real `Installer` records without reintroducing the model this task deletes. There is no automated test for the migration itself — verify it manually instead:

- [ ] **Step 1: Manually verify the migration before deleting `Installer`**

Before touching any model/controller/view/route, run the two new migrations (with `Installer` and its table still present in code) against the **development** database (`RAILS_ENV=development bin/rails db:migrate`), then open `bin/rails console` (development) and check: `ResponsibleType.count` and `Responsible.count` increased by the expected amounts, `ProjectResponsible.count` matches the number of projects that had an installer assigned, and `FieldDefinition.where(reference_table: "installers")` is empty. Only proceed to Step 3 (deleting the `Installer` code) once this checks out.

- [ ] **Step 2: Write the migrations**

```ruby
# db/migrate/<timestamp>_migrate_installers_to_responsibles.rb
class MigrateInstallersToResponsibles < ActiveRecord::Migration[7.2]
  def up
    installer_fields = FieldDefinition.where(reference_table: "installers")
    return if installer_fields.none?

    responsible_type_by_project_type = installer_fields.pluck(:project_type_id).uniq.index_with do |pt_id|
      ResponsibleType.create!(project_type_id: pt_id, name: "Instalador")
    end

    installer_to_responsible = Installer.all.to_h do |installer|
      [installer.id, Responsible.create!(name: installer.name, color: installer.color)]
    end

    installer_fields.each do |field|
      responsible_type = responsible_type_by_project_type[field.project_type_id]
      Project.where(project_type_id: field.project_type_id).find_each do |project|
        installer_id = project.custom_fields[field.key]
        next if installer_id.blank?
        responsible = installer_to_responsible[installer_id.to_i]
        next if responsible.nil?
        ProjectResponsible.create!(project: project, responsible: responsible, responsible_type: responsible_type)
      end
    end

    installer_fields.destroy_all
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
```

```ruby
# db/migrate/<timestamp>_drop_installers.rb
class DropInstallers < ActiveRecord::Migration[7.2]
  def change
    drop_table :installers do |t|
      t.string :name, null: false
      t.string :color, default: "#6c757d", null: false
      t.timestamps
    end
  end
end
```

Run: `bin/rails db:migrate` (this runs against the **test** database's schema too, via the usual `db:test:prepare`/parallel schema load — confirm with `bin/rails test` that fixtures no longer reference `installers` before this passes; see Step 4).

- [ ] **Step 3: Remove `Installer` and everything that references it**

Delete these files:
- `app/models/installer.rb`
- `app/controllers/admin/installers_controller.rb`
- `app/views/admin/installers/index.html.erb`, `_form.html.erb`, `new.html.erb`, `edit.html.erb`
- `test/models/installer_test.rb`
- `test/controllers/admin/installers_controller_test.rb`
- `test/fixtures/installers.yml`

In `config/routes.rb`, remove `resources :installers` from inside `namespace :admin do`.

In `config/locales/es.yml`, remove the `installer: "Instalador"` line under `activerecord.models` and the `installer:` block under `activerecord.attributes`.

In `app/models/project.rb`, remove the `installer` method:

```ruby
  def installer
    key = project_type.field_definitions.find_by(reference_table: "installers")&.key
    return nil if key.nil?

    installer_id = custom_fields[key]
    return nil if installer_id.blank?

    Installer.find_by(id: installer_id)
  end
```

In `test/fixtures/field_definitions.yml`, remove the `instalador:` fixture entry (the "cliente" entry stays).

In `test/models/project_test.rb`, remove the three `installer`-related tests (`"installer resolves the assigned Installer through the dynamic reference field"`, `"installer is nil when no installer has been assigned yet"`, `"installer is nil when the assigned id no longer exists"`) and the `custom_fields` key `"instalador"` reference in `"valid with correct custom_fields types"` and `"invalid when reference field points to a nonexistent installer"` — those two tests exercised the generic `reference` data-type validator using `installers` as the example reference table; rewrite them to use a different `reference_table` so the generic validator still has coverage:

```ruby
  test "valid with correct custom_fields types" do
    project = Project.new(
      project_type: @project_type,
      name: "Instalación Torre Norte",
      custom_fields: { "cliente" => "Acme S.A." }
    )
    assert project.valid?, project.errors.full_messages.to_s
  end
```

(Remove the `"invalid when reference field points to a nonexistent installer"` test outright — the generic `reference` data-type validator itself is not being changed by this plan, and no other `FieldDefinition` fixture with `data_type: "reference"` exists after `instalador` is removed; re-adding one just to keep this test alive is out of scope. If you want to keep coverage for the `reference` validator, that's a pre-existing gap this plan doesn't need to fix.)

- [ ] **Step 4: Run the full suite**

Run: `bin/rails test`
Expected: PASS — no reference to `Installer`, `installers`, or `installer_id` remains anywhere in `app/` or `test/`. Confirm with:

```bash
grep -rli "installer" app/ test/ config/routes.rb config/locales/es.yml
```

Expected: no output.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Migrate Installer data to Responsible and remove Installer entirely"
```
