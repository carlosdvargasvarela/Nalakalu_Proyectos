# Roles y permisos por proyecto Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add three user roles (admin/gerente/visor) with per-project access grants: admin has full access to everything including `/admin/*`; gerente sees all projects but edits only those explicitly granted (and is auto-granted edit on projects they create); visor only sees the specific projects an admin assigned them, never edits. Admin becomes the only way to create users (self-registration removed).

**Architecture:** A `role` enum column on `User` plus a `project_accesses` join table (`user_id`, `project_id`, `can_edit`). Authorization is plain Ruby methods on `User` (`can_view_project?`/`can_edit_project?`) and a `Project.visible_to(user)` scope — no new gem (Pundit/CanCanCan) for 3 roles and one relationship. `Admin::BaseController` gates the whole `/admin/*` namespace to `admin?`. `ApplicationController#require_admin_or_gerente!` gates project/import creation to non-visor roles.

**Tech Stack:** Rails 7.2.3, PostgreSQL, Devise, Minitest + fixtures.

## Global Constraints

- `/admin/*` (project types, field definitions, stage templates, log entry types, installers, users) is exclusive to `admin` — gerente has zero access, not even read-only.
- Permission grants (`ProjectAccess`) are assigned only from the user's own edit page (`/admin/users/:id`), never from the project's page — per spec decision.
- `visor` never creates/edits/comments on a project, regardless of what `ProjectAccess` rows exist for them — view only.
- A `gerente` who creates a project (via `ProjectsController#create` or `ImportsController#create`) is automatically granted `can_edit: true` on it.
- No mailer/`:recoverable` — an admin sets a user's password directly, in plain text, communicated out of band.
- No self-registration — `:registerable` removed from `User`, `/users/sign_up` no longer exists as a route.
- Existing users: `admin@nalakalu.com` → `admin` via migration backfill; any other existing user defaults to `visor` (the column default).
- Out of scope: guaranteeing at least one admin always exists, self-service password change, a 4th role, assigning access from the project's own page.

---

### Task 1: `User.role` enum, migration, backfill, fixtures

**Files:**
- Create: `db/migrate/<timestamp>_add_role_to_users.rb`
- Modify: `app/models/user.rb`
- Modify: `test/fixtures/users.yml`
- Create: `test/models/user_test.rb`

**Interfaces:**
- Produces: `User#role` (string enum: `admin`/`gerente`/`visor`, default `"visor"`), `User#admin?`/`#gerente?`/`#visor?` (Rails enum-generated predicates). Fixtures `juan` (admin), `carla` (gerente), `maria` (visor) — used by every later task's tests.

- [ ] **Step 1: Write the failing model test**

Create `test/models/user_test.rb`:
```ruby
require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "defaults to visor role" do
    user = User.create!(email: "nuevo@example.com", password: "password123")
    assert user.visor?
  end

  test "role accepts admin, gerente, and visor" do
    assert User.new(role: "admin").admin?
    assert User.new(role: "gerente").gerente?
    assert User.new(role: "visor").visor?
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

```bash
bin/rails test test/models/user_test.rb
```
Expected: FAIL — `ActiveModel::UnknownAttributeError: unknown attribute 'role' for User` (column doesn't exist yet).

- [ ] **Step 3: Create and run the migration**

```bash
bin/rails generate migration AddRoleToUsers
```

Replace the generated file with:
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

```bash
bin/rails db:migrate
RAILS_ENV=test bin/rails db:migrate
```
Expected: migrates cleanly on dev and test.

- [ ] **Step 4: Add the enum to `User`**

Read `app/models/user.rb` first. Add the `enum` call below the existing `devise` line — do NOT touch the `devise` line itself (removing `:registerable` is a later task):

```ruby
class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :rememberable, :validatable

  enum :role, { admin: "admin", gerente: "gerente", visor: "visor" }, default: "visor"
end
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
bin/rails test test/models/user_test.rb
```
Expected: PASS (2 tests).

- [ ] **Step 6: Update fixtures**

Read `test/fixtures/users.yml` first. Set `juan` to `admin` (it's already used by every `admin/*` controller test, so keeping it admin means those tests need no changes), and add `carla` (gerente) and `maria` (visor):

```yaml
juan:
  email: juan@example.com
  encrypted_password: <%= Devise::Encryptor.digest(User, "password123") %>
  role: admin

carla:
  email: carla@example.com
  encrypted_password: <%= Devise::Encryptor.digest(User, "password123") %>
  role: gerente

maria:
  email: maria@example.com
  encrypted_password: <%= Devise::Encryptor.digest(User, "password123") %>
  role: visor
```

- [ ] **Step 7: Run the full test suite**

```bash
bin/rails test
```
Expected: PASS, 0 failures, 0 errors — `juan` being `admin` doesn't change behavior yet (no authorization checks exist until Task 2), and the two new fixtures aren't referenced by any test yet.

- [ ] **Step 8: Commit**

```bash
git add db/migrate db/schema.rb app/models/user.rb test/fixtures/users.yml test/models/user_test.rb
git commit -m "Add role enum to User (admin/gerente/visor)"
```

---

### Task 2: `Admin::BaseController` — lock `/admin/*` to admins

**Files:**
- Create: `app/controllers/admin/base_controller.rb`
- Modify: `app/controllers/admin/project_types_controller.rb`
- Modify: `app/controllers/admin/field_definitions_controller.rb`
- Modify: `app/controllers/admin/stage_templates_controller.rb`
- Modify: `app/controllers/admin/log_entry_types_controller.rb`
- Modify: `app/controllers/admin/installers_controller.rb`
- Test: `test/controllers/admin/authorization_test.rb`

**Interfaces:**
- Consumes: `User#admin?` (Task 1).
- Produces: `Admin::BaseController` — every controller under `admin/`, including Task 6's new `Admin::UsersController`, inherits from this instead of `ApplicationController` directly.

- [ ] **Step 1: Write the failing test**

Create `test/controllers/admin/authorization_test.rb`:
```ruby
require "test_helper"

class Admin::AuthorizationTest < ActionDispatch::IntegrationTest
  test "admin can access admin controllers" do
    sign_in users(:juan)
    get admin_installers_path
    assert_response :success
  end

  test "gerente is redirected away from admin controllers" do
    sign_in users(:carla)
    get admin_installers_path
    assert_redirected_to root_path
    assert_equal "No tenés permiso para acceder a esa sección.", flash[:alert]
  end

  test "visor is redirected away from admin controllers" do
    sign_in users(:maria)
    get admin_installers_path
    assert_redirected_to root_path
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

```bash
bin/rails test test/controllers/admin/authorization_test.rb
```
Expected: FAIL on the gerente/visor tests — today anyone authenticated gets `:success`, not a redirect.

- [ ] **Step 3: Create `Admin::BaseController`**

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

- [ ] **Step 4: Change each admin controller's superclass**

In each of these 5 files, change `class Admin::XController < ApplicationController` to `class Admin::XController < Admin::BaseController`. Everything else in each file stays the same — read each file first, this is a one-line change per file:
- `app/controllers/admin/project_types_controller.rb`
- `app/controllers/admin/field_definitions_controller.rb`
- `app/controllers/admin/stage_templates_controller.rb`
- `app/controllers/admin/log_entry_types_controller.rb`
- `app/controllers/admin/installers_controller.rb`

- [ ] **Step 5: Run the test to verify it passes**

```bash
bin/rails test test/controllers/admin/authorization_test.rb
```
Expected: PASS (3 tests).

- [ ] **Step 6: Run the full suite**

```bash
bin/rails test
```
Expected: PASS, 0 failures, 0 errors — all existing `admin/*` tests `sign_in users(:juan)`, who is now `admin`, so they're unaffected.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/admin test/controllers/admin/authorization_test.rb
git commit -m "Restrict /admin/* to the admin role"
```

---

### Task 3: `ProjectAccess` model + `User`/`Project` authorization methods

**Files:**
- Create: `db/migrate/<timestamp>_create_project_accesses.rb`
- Create: `app/models/project_access.rb`
- Modify: `app/models/user.rb`
- Modify: `app/models/project.rb`
- Create: `test/models/project_access_test.rb`
- Modify: `test/models/user_test.rb`
- Modify: `test/models/project_test.rb`

**Interfaces:**
- Produces: `ProjectAccess(user_id, project_id, can_edit)`; `user.project_accesses`, `user.can_view_project?(project)`, `user.can_edit_project?(project)`; `project.project_accesses`; `Project.visible_to(user)`. Task 4/5 controllers and Task 6's admin UI all consume these.

- [ ] **Step 1: Write the failing tests**

Create `test/models/project_access_test.rb`:
```ruby
require "test_helper"

class ProjectAccessTest < ActiveSupport::TestCase
  setup do
    @project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
  end

  test "valid with user and project" do
    access = ProjectAccess.new(user: users(:maria), project: @project)
    assert access.valid?
  end

  test "invalid with a duplicate user/project pair" do
    ProjectAccess.create!(user: users(:maria), project: @project)
    dup = ProjectAccess.new(user: users(:maria), project: @project)
    assert_not dup.valid?
  end

  test "can_edit defaults to false" do
    access = ProjectAccess.create!(user: users(:maria), project: @project)
    assert_equal false, access.can_edit
  end
end
```

Add to `test/models/user_test.rb` (read the file first, append below the existing tests):
```ruby
test "admin can view and edit any project" do
  project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
  assert users(:juan).can_view_project?(project)
  assert users(:juan).can_edit_project?(project)
end

test "gerente can view any project but only edit those with can_edit access" do
  project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
  gerente = users(:carla)
  assert gerente.can_view_project?(project)
  assert_not gerente.can_edit_project?(project)

  ProjectAccess.create!(user: gerente, project: project, can_edit: true)
  assert gerente.can_edit_project?(project)
end

test "visor can only view projects with an access row, and never edits" do
  project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
  visor = users(:maria)
  assert_not visor.can_view_project?(project)
  assert_not visor.can_edit_project?(project)

  ProjectAccess.create!(user: visor, project: project, can_edit: true)
  assert visor.can_view_project?(project)
  assert_not visor.can_edit_project?(project)
end
```

Add to `test/models/project_test.rb` (read the file first, append below the existing tests):
```ruby
test "visible_to returns all projects for admin and gerente" do
  project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
  assert_includes Project.visible_to(users(:juan)), project
  assert_includes Project.visible_to(users(:carla)), project
end

test "visible_to returns only accessible projects for visor" do
  project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
  other = Project.create!(project_type: project_types(:instalaciones), name: "Torre Sur", custom_fields: {})
  ProjectAccess.create!(user: users(:maria), project: project)

  visible = Project.visible_to(users(:maria))
  assert_includes visible, project
  assert_not_includes visible, other
end
```

- [ ] **Step 2: Run all three to verify they fail**

```bash
bin/rails test test/models/project_access_test.rb test/models/user_test.rb test/models/project_test.rb
```
Expected: FAIL — `uninitialized constant ProjectAccess` / `NoMethodError` for `can_view_project?`/`can_edit_project?`/`visible_to`.

- [ ] **Step 3: Create the migration and model**

```bash
bin/rails generate migration CreateProjectAccesses
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

```ruby
# app/models/project_access.rb
class ProjectAccess < ApplicationRecord
  belongs_to :user
  belongs_to :project

  validates :user_id, uniqueness: { scope: :project_id }
end
```

```bash
bin/rails db:migrate
RAILS_ENV=test bin/rails db:migrate
```

- [ ] **Step 4: Add methods to `User`**

Read `app/models/user.rb` first (it now has the `enum` from Task 1). Add below the `enum` line:
```ruby
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
```

- [ ] **Step 5: Add to `Project`**

Read `app/models/project.rb` first. Add `has_many :project_accesses, dependent: :destroy` alongside the existing `has_many :project_stages, dependent: :destroy` / `has_many :log_entries, dependent: :destroy`, and add the class method (public, near the top of the class body, before the instance methods):
```ruby
def self.visible_to(user)
  return all if user.admin? || user.gerente?
  joins(:project_accesses).where(project_accesses: { user_id: user.id })
end
```

- [ ] **Step 6: Run the tests to verify they pass**

```bash
bin/rails test test/models/project_access_test.rb test/models/user_test.rb test/models/project_test.rb
```
Expected: PASS (all tests in all three files).

- [ ] **Step 7: Run the full suite**

```bash
bin/rails test
```
Expected: PASS, 0 failures, 0 errors.

- [ ] **Step 8: Commit**

```bash
git add db/migrate db/schema.rb app/models/project_access.rb app/models/user.rb app/models/project.rb test/models/project_access_test.rb test/models/user_test.rb test/models/project_test.rb
git commit -m "Add ProjectAccess and per-project authorization methods"
```

---

### Task 4: `ProjectsController` authorization + view gating

**Files:**
- Modify: `app/controllers/application_controller.rb`
- Modify: `app/controllers/projects_controller.rb`
- Modify: `app/views/projects/show.html.erb`
- Modify: `app/views/projects/index.html.erb`
- Modify: `app/views/projects/_project_type_section.html.erb`
- Test: `test/controllers/projects_controller_test.rb`

**Interfaces:**
- Consumes: `User#can_view_project?`/`#can_edit_project?`, `Project.visible_to` (Task 3).
- Produces: `ApplicationController#require_admin_or_gerente!` (private), reused by Task 5's `ImportsController`.

- [ ] **Step 1: Write the failing tests**

Append to `test/controllers/projects_controller_test.rb` (read the file first — top-level `setup { sign_in users(:juan) }` applies unless a test re-signs-in):

```ruby
test "index only lists projects visible to a visor" do
  visible = Project.create!(project_type: project_types(:instalaciones), name: "Torre Visible", custom_fields: {})
  hidden = Project.create!(project_type: project_types(:instalaciones), name: "Torre Oculta", custom_fields: {})
  ProjectAccess.create!(user: users(:maria), project: visible)

  sign_in users(:maria)
  get projects_path

  assert_response :success
  assert_select "body", /Torre Visible/
  assert_select "body", text: /Torre Oculta/, count: 0
end

test "show redirects a visor without access to the project" do
  project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})

  sign_in users(:maria)
  get project_path(project)

  assert_redirected_to projects_path
end

test "show allows a visor with access, but hides edit controls" do
  project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
  ProjectAccess.create!(user: users(:maria), project: project)

  sign_in users(:maria)
  get project_path(project)

  assert_response :success
  assert_select "a[href=?]", edit_project_path(project), count: 0
end

test "edit redirects a gerente without edit access to the project" do
  project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})

  sign_in users(:carla)
  get edit_project_path(project)

  assert_redirected_to projects_path
end

test "edit allows a gerente with edit access" do
  project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
  ProjectAccess.create!(user: users(:carla), project: project, can_edit: true)

  sign_in users(:carla)
  get edit_project_path(project)

  assert_response :success
end

test "new and create are blocked for a visor" do
  sign_in users(:maria)
  get new_project_path(project_type_id: project_types(:instalaciones).id)
  assert_redirected_to root_path

  assert_no_difference("Project.count") do
    post projects_path, params: { project: { project_type_id: project_types(:instalaciones).id, name: "Torre Norte", custom_fields: {} } }
  end
end

test "create as a gerente automatically grants the creator edit access" do
  sign_in users(:carla)
  post projects_path, params: {
    project: { project_type_id: project_types(:instalaciones).id, name: "Torre Nueva", custom_fields: {} }
  }

  project = Project.find_by(name: "Torre Nueva")
  assert users(:carla).can_edit_project?(project)
end

test "bulk_assign_installer only updates projects the gerente can edit" do
  editable = Project.create!(project_type: project_types(:instalaciones), name: "Torre Editable", custom_fields: {})
  not_editable = Project.create!(project_type: project_types(:instalaciones), name: "Torre No Editable", custom_fields: {})
  ProjectAccess.create!(user: users(:carla), project: editable, can_edit: true)

  sign_in users(:carla)
  patch bulk_assign_installer_projects_path, params: {
    project_ids: [editable.id, not_editable.id], installer_id: installers(:juan_perez).id
  }

  key = project_types(:instalaciones).field_definitions.find_by(reference_table: "installers").key
  assert_equal installers(:juan_perez).id.to_s, editable.reload.custom_fields[key]
  assert_nil not_editable.reload.custom_fields[key]
end
```

- [ ] **Step 2: Run them to verify they fail**

```bash
bin/rails test test/controllers/projects_controller_test.rb
```
Expected: FAIL on all the new tests (no authorization exists yet) — the existing tests in this file should still pass (they all run as `juan`/admin).

- [ ] **Step 3: Add `require_admin_or_gerente!` to `ApplicationController`**

Read the file first:
```ruby
class ApplicationController < ActionController::Base
  allow_browser versions: :modern

  before_action :authenticate_user!, unless: :devise_controller?
  before_action :set_paper_trail_whodunnit

  private

  def require_admin_or_gerente!
    return if current_user.admin? || current_user.gerente?
    redirect_to root_path, alert: "No tenés permiso para hacer eso."
  end
end
```

- [ ] **Step 4: Update `ProjectsController`**

Read the full current file first. Add `before_action`s and the two new private methods, and update `build_section`, `tracker`, `create`, and `bulk_assign_installer`:

```ruby
class ProjectsController < ApplicationController
  before_action :set_project, only: [:show, :edit, :update]
  before_action :require_admin_or_gerente!, only: [:new, :create, :bulk_assign_installer]
  before_action :authorize_view!, only: [:show]
  before_action :authorize_edit!, only: [:edit, :update]

  def index
    @statuses = Project.distinct.pluck(:status).compact
    @installers = Installer.all
    @sections = ProjectType.all.map { |project_type| build_section(project_type) }
  end

  def tracker
    @project_types = ProjectType.all
    @installers = Installer.all
    @project_type = ProjectType.find_by(id: params[:project_type_id]) || ProjectType.first
    @projects = if @project_type
      scope = Project.visible_to(current_user).where(project_type: @project_type).where.not(status: "archived")
                     .includes(project_stages: :stage_template).order(:name)
      params[:installer_id].present? ? filter_by_installer(scope, params[:installer_id]) : scope
    else
      Project.none
    end
  end

  def show
    @project_change_versions = PaperTrail::Version
      .where(item_type: "Project", item_id: @project.id)
      .or(PaperTrail::Version.where(item_type: "ProjectStage", item_id: @project.project_stage_ids))
      .order(created_at: :desc)
      .limit(50)

    whodunnit_ids = @project_change_versions.map(&:whodunnit).compact
    @version_authors = User.where(id: whodunnit_ids).index_by { |u| u.id.to_s }
  end

  def new
    @project_type = ProjectType.find(params[:project_type_id]) if params[:project_type_id]
    @project = Project.new(project_type: @project_type)
  end

  def create
    @project = Project.new(project_params)
    @project_type = @project.project_type
    if @project.save
      ProjectAccess.create!(user: current_user, project: @project, can_edit: true) if current_user.gerente?
      redirect_to project_path(@project)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @project_type = @project.project_type
  end

  def update
    @project_type = @project.project_type
    if @project.update(project_params)
      respond_to do |format|
        format.html { redirect_to project_path(@project) }
        format.json { render json: stage_payload }
      end
    else
      respond_to do |format|
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: { errors: @project.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def bulk_assign_installer
    project_ids = Array(params[:project_ids]).reject(&:blank?)
    if params[:installer_id].blank? || project_ids.empty?
      redirect_to projects_path(request.query_parameters), alert: "Elegí un instalador y al menos un proyecto." and return
    end

    editable_projects = Project.visible_to(current_user).where(id: project_ids).select { |project| current_user.can_edit_project?(project) }
    count = 0
    editable_projects.each do |project|
      key = project.project_type.field_definitions.find_by(reference_table: "installers")&.key
      next unless key

      project.custom_fields = project.custom_fields.merge(key => params[:installer_id])
      count += 1 if project.save
    end

    redirect_to projects_path(request.query_parameters), notice: "Instalador asignado a #{count} proyecto(s)."
  end

  private

  def set_project
    @project = Project.find(params[:id])
  end

  def authorize_view!
    return if current_user.can_view_project?(@project)
    redirect_to projects_path, alert: "No tenés acceso a ese proyecto."
  end

  def authorize_edit!
    return if current_user.can_edit_project?(@project)
    redirect_to projects_path, alert: "No tenés permiso para editar ese proyecto."
  end

  def project_params
    params.require(:project).permit(
      :project_type_id, :name, :status, custom_fields: {},
      project_stages_attributes: [:id, :start_date, :end_date, :progress_percent]
    )
  end

  def stage_payload
    @project.project_stages.map do |stage|
      { id: stage.id, start_date: stage.start_date, end_date: stage.end_date, progress_percent: stage.progress_percent }
    end
  end

  def filter_by_installer(scope, installer_id)
    keys = FieldDefinition.where(reference_table: "installers").distinct.pluck(:key)
    return scope.none if keys.empty?
    keys.map { |key| scope.where("custom_fields ->> ? = ?", key, installer_id.to_s) }.reduce(:or)
  end

  def filter_by_no_installer(scope)
    keys = FieldDefinition.where(reference_table: "installers").distinct.pluck(:key)
    return scope if keys.empty?
    keys.reduce(scope) { |s, key| s.where("custom_fields ->> ? IS NULL OR custom_fields ->> ? = ''", key, key) }
  end

  def filter_by_date_range(scope, from_date, to_date)
    return scope if from_date.blank? && to_date.blank?

    dated_scope = scope.joins(:project_stages).distinct
    dated_scope = dated_scope.where("project_stages.end_date >= ?", from_date) if from_date.present?
    dated_scope = dated_scope.where("project_stages.start_date <= ?", to_date) if to_date.present?

    dated_stage_project_ids = ProjectStage.where.not(start_date: nil).where.not(end_date: nil).select(:project_id)
    undated_scope = scope.where.not(id: dated_stage_project_ids)

    scope.where(id: dated_scope.reorder(nil).select(:id)).or(scope.where(id: undated_scope.reorder(nil).select(:id)))
  end

  def filter_by_query(scope, q)
    return scope if q.blank?
    term = "%#{q}%"
    scope.where("projects.name ILIKE :term OR projects.custom_fields::text ILIKE :term", term: term)
  end

  def build_section(project_type)
    section_submitted = params.dig(:sections, project_type.slug)
    section_params = section_submitted || {}

    projects = Project.visible_to(current_user).where(project_type: project_type).includes(:project_type, project_stages: :stage_template).order(:name)
    projects = section_params[:status].present? ? projects.where(status: section_params[:status]) : projects.where.not(status: "archived")
    if section_params[:installer_id] == "none"
      projects = filter_by_no_installer(projects)
    elsif section_params[:installer_id].present?
      projects = filter_by_installer(projects, section_params[:installer_id])
    end
    projects = filter_by_date_range(projects, section_params[:from_date], section_params[:to_date])
    projects = filter_by_query(projects, section_params[:q])

    projects_list = projects.to_a
    per_page = 20
    page = [section_params[:page].to_i, 1].max
    total_pages = (projects_list.size / per_page.to_f).ceil
    page_projects = projects_list.drop((page - 1) * per_page).first(per_page)
    stage_names = StageTemplate.where(project_type: project_type).order(:name).pluck(:name)

    stage_name = if section_submitted.nil?
      project_type.stage_templates.find_by(default_in_filter: true)&.name
    else
      section_params[:stage_name]
    end

    {
      project_type: project_type,
      params: section_params,
      stage_name: stage_name,
      projects_list: projects_list,
      page_projects: page_projects,
      page: page,
      total_pages: total_pages,
      stage_names: stage_names
    }
  end
end
```

(Only `tracker`, `create`, `bulk_assign_installer`, `build_section`, and the two new `before_action`s/private methods changed from the original — everything else shown above is unchanged, reproduced in full because this is the whole file.)

- [ ] **Step 5: Gate edit controls in `app/views/projects/show.html.erb`**

Read the full file first. Wrap the "Editar"/archive button block:
```erb
  <% if current_user.can_edit_project?(@project) %>
    <div class="d-flex gap-2">
      <%= link_to edit_project_path(@project), class: "btn btn-outline-secondary btn-sm" do %>
        <i class="bi bi-pencil"></i> Editar
      <% end %>
      <%= render "archive_button", project: @project %>
    </div>
  <% end %>
```

Wrap the stage table partial (inside the Cronograma card, currently `<%= render "stage_table", project: @project %>` on its own line):
```erb
    <% if current_user.can_edit_project?(@project) %>
      <%= render "stage_table", project: @project %>
    <% end %>
```

Wrap the bitácora add-form (the `<%= form_with model: LogEntry.new ... %>` block through its closing `<script>` tag with the `trix-file-accept` listener) — the entry list below it (`<ul class="list-group list-group-flush">...</ul>`) stays unconditional:
```erb
    <% if current_user.can_edit_project?(@project) %>
      <%= form_with model: LogEntry.new, url: project_log_entries_path(@project), class: "mb-3" do |f| %>
        <%= f.rich_text_area :body, id: "bitacora-trix-editor", class: "trix-content mb-2" %>
        <div class="d-flex gap-2">
          <%= f.collection_select :log_entry_type_id, @project.project_type.log_entry_types, :id, :name, {}, class: "form-select form-select-sm w-auto" %>
          <%= f.submit "Agregar", class: "btn btn-primary btn-sm" %>
        </div>
      <% end %>
      <script>
        document.getElementById("bitacora-trix-editor").addEventListener("trix-file-accept", function (event) {
          event.preventDefault();
        });
      </script>
    <% end %>
```

(The Gantt chart's drag-to-edit stays visible/interactive for everyone who can view — a save attempt from a non-editor fails server-side and the existing JS `.catch` handler already reverts the chart and shows an alert, so this isn't a silent failure. Not worth a "read-only Gantt mode" for this pass.)

- [ ] **Step 6: Gate "Nuevo proyecto" in `app/views/projects/index.html.erb`**

Read the file first. Wrap the dropdown:
```erb
<div class="d-flex justify-content-between align-items-center mb-3">
  <h1 class="mb-0">Proyectos</h1>
  <% if current_user.admin? || current_user.gerente? %>
    <div class="dropdown">
      <button class="btn btn-primary dropdown-toggle" type="button" data-bs-toggle="dropdown" aria-expanded="false">
        Nuevo proyecto
      </button>
      <ul class="dropdown-menu dropdown-menu-end">
        <% ProjectType.all.each do |project_type| %>
          <li><%= link_to project_type.name, new_project_path(project_type_id: project_type.id), class: "dropdown-item" %></li>
        <% end %>
      </ul>
    </div>
  <% end %>
</div>
```

- [ ] **Step 7: Gate per-row edit controls and bulk-assign in `app/views/projects/_project_type_section.html.erb`**

Read the full file first. Wrap the entire bulk-assign form (`<%= form_with url: bulk_assign_installer_projects_path... %> ... <% end %>`) with `<% if current_user.admin? || current_user.gerente? %> ... <% end %>`.

Wrap the header checkbox cell:
```erb
            <% if current_user.admin? || current_user.gerente? %><th><input type="checkbox" id="select-all-projects-<%= slug %>"></th><% end %>
```

Wrap each row's checkbox cell (inside the `page_projects.each` loop):
```erb
              <% if current_user.admin? || current_user.gerente? %><td><%= check_box_tag "project_ids[]", project.id, false, id: nil, form: "bulk-assign-form-#{slug}" %></td><% end %>
```

Wrap each row's Editar/Archivar cell contents with a per-project check (independent of the bulk-assign visibility above — a gerente might see the bulk-assign UI but not be able to edit this particular row):
```erb
              <td>
                <% if current_user.can_edit_project?(project) %>
                  <div class="d-flex gap-2">
                    <%= link_to edit_project_path(project), class: "btn btn-outline-secondary btn-sm" do %>
                      <i class="bi bi-pencil"></i> Editar
                    <% end %>
                    <%= render "archive_button", project: project %>
                  </div>
                <% end %>
              </td>
```

- [ ] **Step 8: Run the projects controller tests to verify they pass**

```bash
bin/rails test test/controllers/projects_controller_test.rb
```
Expected: PASS (all tests, old and new).

- [ ] **Step 9: Run the full suite**

```bash
bin/rails test
```
Expected: PASS, 0 failures, 0 errors.

- [ ] **Step 10: Commit**

```bash
git add app/controllers/application_controller.rb app/controllers/projects_controller.rb app/views/projects/show.html.erb app/views/projects/index.html.erb app/views/projects/_project_type_section.html.erb test/controllers/projects_controller_test.rb
git commit -m "Authorize ProjectsController and gate edit UI by role/access"
```

---

### Task 5: `LogEntriesController` and `ImportsController` authorization

**Files:**
- Modify: `app/controllers/log_entries_controller.rb`
- Modify: `app/controllers/imports_controller.rb`
- Test: `test/controllers/log_entries_controller_test.rb`
- Test: `test/controllers/imports_controller_test.rb`

**Interfaces:**
- Consumes: `User#can_edit_project?` (Task 3), `ApplicationController#require_admin_or_gerente!` (Task 4).

- [ ] **Step 1: Write the failing log-entry tests**

Read `test/controllers/log_entries_controller_test.rb` first, then append:
```ruby
test "create is blocked for a visor even with view access" do
  project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
  ProjectAccess.create!(user: users(:maria), project: project)

  sign_in users(:maria)
  assert_no_difference("project.log_entries.count") do
    post project_log_entries_path(project), params: {
      log_entry: { body: "Intento de nota", log_entry_type_id: log_entry_types(:nota).id }
    }
  end
end

test "create is blocked for a gerente without edit access" do
  project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})

  sign_in users(:carla)
  assert_no_difference("project.log_entries.count") do
    post project_log_entries_path(project), params: {
      log_entry: { body: "Intento de nota", log_entry_type_id: log_entry_types(:nota).id }
    }
  end
end

test "create succeeds for a gerente with edit access" do
  project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
  ProjectAccess.create!(user: users(:carla), project: project, can_edit: true)

  sign_in users(:carla)
  assert_difference("project.log_entries.count", 1) do
    post project_log_entries_path(project), params: {
      log_entry: { body: "Nota autorizada", log_entry_type_id: log_entry_types(:nota).id }
    }
  end
end
```

- [ ] **Step 2: Write the failing imports tests**

Read `test/controllers/imports_controller_test.rb` first, then append:
```ruby
test "new is blocked for a visor" do
  sign_in users(:maria)
  get new_import_path
  assert_redirected_to root_path
end

test "create as a gerente grants edit access on each imported project" do
  sign_in users(:carla)
  project_type = project_types(:instalaciones)
  csv = "Nombre,Cliente,Instalador\nTorre Norte,Acme S.A.,Juan Pérez\n"

  post imports_path, params: {
    project_type_id: project_type.id,
    file: Rack::Test::UploadedFile.new(StringIO.new(csv), "text/csv", original_filename: "plantilla.csv")
  }

  project = Project.find_by(name: "Torre Norte")
  assert users(:carla).can_edit_project?(project)
end
```

- [ ] **Step 3: Run both files to verify the new tests fail**

```bash
bin/rails test test/controllers/log_entries_controller_test.rb test/controllers/imports_controller_test.rb
```
Expected: FAIL on the new tests — no authorization exists yet. Existing tests in both files (all run as `juan`/admin) should still pass.

- [ ] **Step 4: Update `LogEntriesController`**

Read the file first:
```ruby
class LogEntriesController < ApplicationController
  before_action :set_project
  before_action :authorize_edit!, only: [:create]

  def create
    @log_entry = @project.log_entries.new(log_entry_params.merge(user: current_user))
    if @log_entry.save
      redirect_to project_path(@project)
    else
      redirect_to project_path(@project), alert: @log_entry.errors.full_messages.to_sentence
    end
  end

  def destroy
    log_entry = @project.log_entries.find(params[:id])
    log_entry.destroy if log_entry.user == current_user
    redirect_to project_path(@project)
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end

  def authorize_edit!
    return if current_user.can_edit_project?(@project)
    redirect_to project_path(@project), alert: "No tenés permiso para agregar notas a este proyecto."
  end

  def log_entry_params
    params.require(:log_entry).permit(:body, :log_entry_type_id)
  end
end
```

- [ ] **Step 5: Update `ImportsController`**

Read the file first:
```ruby
require "csv"

class ImportsController < ApplicationController
  before_action :require_admin_or_gerente!

  def new
    @project_types = ProjectType.all
    @project_type = ProjectType.find_by(id: params[:project_type_id])
  end

  def template
    project_type = ProjectType.find(params[:project_type_id])
    send_data csv_template_for(project_type), filename: "plantilla-#{project_type.slug}.csv", type: "text/csv"
  end

  def create
    @project_type = ProjectType.find(params[:project_type_id])
    @project_types = ProjectType.all
    @results = import_rows(@project_type, params[:file])
    render :new
  end

  private

  def csv_template_for(project_type)
    fields = project_type.field_definitions.order(:position)
    CSV.generate do |csv|
      csv << ["Nombre"] + fields.map(&:label)
    end
  end

  def import_rows(project_type, file)
    return { created: 0, errors: [{ row: 0, message: "No se subió ningún archivo" }] } if file.blank?

    fields = project_type.field_definitions.order(:position).to_a
    rows = CSV.parse(file.read.force_encoding("UTF-8").sub("﻿", ""), headers: true)
    created = 0
    row_errors = []

    rows.each_with_index do |row, index|
      custom_fields = fields.each_with_object({}) do |field, hash|
        hash[field.key] = resolve_field_value(field, row[field.label])
      end
      project = Project.new(project_type: project_type, name: row["Nombre"], custom_fields: custom_fields)
      if project.save
        ProjectAccess.create!(user: current_user, project: project, can_edit: true) if current_user.gerente?
        created += 1
      else
        row_errors << { row: index + 2, message: project.errors.full_messages.join(", ") }
      end
    end

    { created: created, errors: row_errors }
  end

  def resolve_field_value(field, raw_value)
    return raw_value if raw_value.blank? || field.data_type != "reference"

    record = field.reference_table.classify.constantize.find_by(name: raw_value.strip)
    record ? record.id : "#{raw_value} (no encontrado)"
  end
end
```

- [ ] **Step 6: Run both test files to verify they pass**

```bash
bin/rails test test/controllers/log_entries_controller_test.rb test/controllers/imports_controller_test.rb
```
Expected: PASS (all tests, old and new).

- [ ] **Step 7: Run the full suite**

```bash
bin/rails test
```
Expected: PASS, 0 failures, 0 errors.

- [ ] **Step 8: Commit**

```bash
git add app/controllers/log_entries_controller.rb app/controllers/imports_controller.rb test/controllers/log_entries_controller_test.rb test/controllers/imports_controller_test.rb
git commit -m "Authorize LogEntriesController and ImportsController by project access"
```

---

### Task 6: `Admin::UsersController`, no self-registration, navbar

**Files:**
- Modify: `config/routes.rb`
- Modify: `app/models/user.rb`
- Delete: `app/views/devise/registrations/new.html.erb`
- Delete: `app/views/devise/registrations/edit.html.erb`
- Create: `app/controllers/admin/users_controller.rb`
- Create: `app/views/admin/users/index.html.erb`
- Create: `app/views/admin/users/new.html.erb`
- Create: `app/views/admin/users/edit.html.erb`
- Create: `app/views/admin/users/_form.html.erb`
- Modify: `app/helpers/application_helper.rb`
- Modify: `app/views/layouts/_navbar.html.erb`
- Test: `test/controllers/admin/users_controller_test.rb`

**Interfaces:**
- Consumes: `Admin::BaseController` (Task 2), `User#role` (Task 1), `ProjectAccess` (Task 3).

- [ ] **Step 1: Write the failing tests**

Create `test/controllers/admin/users_controller_test.rb`:
```ruby
require "test_helper"

class Admin::UsersControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:juan) }

  test "index lists users" do
    get admin_users_path
    assert_response :success
    assert_select "body", /carla@example.com/
  end

  test "create adds a new user with a role" do
    assert_difference("User.count", 1) do
      post admin_users_path, params: {
        user: { email: "nuevo@example.com", password: "password123", password_confirmation: "password123", role: "gerente" }
      }
    end
    assert_redirected_to admin_users_path
    assert User.find_by(email: "nuevo@example.com").gerente?
  end

  test "create with blank email re-renders form with error" do
    assert_no_difference("User.count") do
      post admin_users_path, params: { user: { email: "", password: "password123", password_confirmation: "password123", role: "visor" } }
    end
    assert_response :unprocessable_entity
  end

  test "update changes the role without requiring a password" do
    patch admin_user_path(users(:maria)), params: { user: { email: users(:maria).email, role: "gerente" } }
    assert_redirected_to admin_users_path
    assert users(:maria).reload.gerente?
  end

  test "update with a password changes it" do
    patch admin_user_path(users(:maria)), params: {
      user: { email: users(:maria).email, role: "visor", password: "nuevapass123", password_confirmation: "nuevapass123" }
    }
    assert_redirected_to admin_users_path
    assert users(:maria).reload.valid_password?("nuevapass123")
  end

  test "update assigns project access from the checkboxes" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    patch admin_user_path(users(:maria)), params: {
      user: { email: users(:maria).email, role: "visor" },
      sync_project_access: "1",
      project_access: { project.id.to_s => { "view" => "1", "edit" => "0" } }
    }
    assert users(:maria).reload.can_view_project?(project)
    assert_not users(:maria).can_edit_project?(project)
  end

  test "update without the access-form marker does not touch existing project access" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    ProjectAccess.create!(user: users(:maria), project: project)

    patch admin_user_path(users(:maria)), params: { user: { email: users(:maria).email, role: "visor" } }

    assert users(:maria).reload.can_view_project?(project)
  end

  test "destroy removes a user" do
    target = User.create!(email: "temporal@example.com", password: "password123", role: "visor")
    assert_difference("User.count", -1) do
      delete admin_user_path(target)
    end
  end

  test "gerente and visor cannot access admin users" do
    sign_in users(:carla)
    get admin_users_path
    assert_redirected_to root_path

    sign_in users(:maria)
    get admin_users_path
    assert_redirected_to root_path
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

```bash
bin/rails test test/controllers/admin/users_controller_test.rb
```
Expected: FAIL — `uninitialized constant Admin::UsersController` (no route yet either).

- [ ] **Step 3: Add the route**

Read `config/routes.rb` first. Change `devise_for :users` to skip registrations, and add `resources :users` under the `admin` namespace:
```ruby
Rails.application.routes.draw do
  devise_for :users, skip: [:registerable]
  get "up" => "rails/health#show", as: :rails_health_check
  get "manifest.json" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker.js" => "rails/pwa#service_worker", as: :pwa_service_worker

  namespace :admin do
    resources :users
    resources :project_types do
      resources :field_definitions, except: [:index, :show] do
        patch :reorder, on: :collection
      end
      resources :stage_templates, except: [:index, :show] do
        patch :reorder, on: :collection
      end
      resources :log_entry_types, except: [:index, :show]
    end
    resources :installers
  end

  get "projects/seguimiento", to: "projects#tracker", as: :tracker_projects
  patch "projects/bulk_assign_installer", to: "projects#bulk_assign_installer", as: :bulk_assign_installer_projects
  resources :projects do
    resources :log_entries, only: [:create, :destroy]
  end

  resources :imports, only: [:new, :create]
  get "imports/template", to: "imports#template", as: :template_imports

  root "projects#index"
end
```

- [ ] **Step 4: Remove `:registerable` from `User`**

Read `app/models/user.rb` first:
```ruby
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

- [ ] **Step 5: Delete the now-unreachable Devise registration views**

```bash
git rm app/views/devise/registrations/new.html.erb app/views/devise/registrations/edit.html.erb
```

- [ ] **Step 6: Add role labels to `ApplicationHelper`**

Read `app/helpers/application_helper.rb` first (it already has `STATUS_LABELS` following this exact pattern). Add:
```ruby
ROLE_LABELS = { "admin" => "Administrador", "gerente" => "Gerente", "visor" => "Visor" }.freeze
```
as a constant alongside the existing ones, and a helper method alongside `status_label`:
```ruby
def role_label(role)
  ROLE_LABELS.fetch(role, role)
end
```

- [ ] **Step 7: Create `Admin::UsersController`**

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

  # ponytail: replaces all of the user's accesses on every save — O(proyectos totales),
  # fine at this pilot's scale. If the project count grows large, upgrade to diffing
  # (only create/destroy what changed) instead of destroy_all + recreate.
  #
  # Only runs when the request actually came from the access-grants form (marked by
  # `sync_project_access`). The email/role/password form is separate and never submits
  # `project_access` at all — without this guard, saving that form would see an absent
  # `project_access` param and wipe every existing grant.
  def sync_project_accesses!
    return unless params[:sync_project_access] == "1"

    submitted = params.fetch(:project_access, {})
    @user.project_accesses.destroy_all
    submitted.each do |project_id, flags|
      next unless flags["view"] == "1"
      @user.project_accesses.create!(project_id: project_id, can_edit: flags["edit"] == "1")
    end
  end
end
```

- [ ] **Step 8: Create the views**

`app/views/admin/users/index.html.erb`:
```erb
<h1>Usuarios</h1>
<%= link_to "Nuevo usuario", new_admin_user_path, class: "btn btn-primary mb-3" %>
<table class="table">
  <thead>
    <tr><th>Correo electrónico</th><th>Rol</th><th></th></tr>
  </thead>
  <tbody>
    <% @users.each do |user| %>
      <tr>
        <td><%= user.email %></td>
        <td><%= role_label(user.role) %></td>
        <td>
          <%= link_to "Editar", edit_admin_user_path(user), class: "btn btn-outline-secondary btn-sm" %>
          <%= button_to "Eliminar", admin_user_path(user), method: :delete,
                class: "btn btn-outline-danger btn-sm", form: { style: "display:inline-block", onsubmit: "return confirm('¿Eliminar usuario?')" } %>
        </td>
      </tr>
    <% end %>
  </tbody>
</table>
```

`app/views/admin/users/_form.html.erb`:
```erb
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

<% if user.persisted? %>
  <hr>
  <h2 class="h5">Accesos a proyectos</h2>
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
```

`app/views/admin/users/new.html.erb`:
```erb
<h1>Nuevo usuario</h1>
<%= render "form", user: @user %>
```

`app/views/admin/users/edit.html.erb`:
```erb
<h1>Editar usuario</h1>
<%= render "form", user: @user %>
```

- [ ] **Step 9: Update the navbar**

Read `app/views/layouts/_navbar.html.erb` first. Remove the "Registrarse" link, and add a "Usuarios" link visible only to admins, next to "Administración":
```erb
<nav class="navbar navbar-expand-lg navbar-light bg-light mb-4">
  <div class="container-fluid">
    <%= link_to "Nalakalu Proyectos", root_path, class: "navbar-brand" %>
    <div class="navbar-nav me-auto">
      <%= link_to "Proyectos", projects_path, class: "nav-link" %>
      <%= link_to "Seguimiento", tracker_projects_path, class: "nav-link" %>
      <% if user_signed_in? && (current_user.admin? || current_user.gerente?) %>
        <%= link_to "Importar", new_import_path, class: "nav-link" %>
      <% end %>
      <% if user_signed_in? && current_user.admin? %>
        <%= link_to "Administración", admin_project_types_path, class: "nav-link" %>
        <%= link_to "Usuarios", admin_users_path, class: "nav-link" %>
      <% end %>
    </div>
    <div class="navbar-nav">
      <% if user_signed_in? %>
        <span class="navbar-text me-3"><%= current_user.email %></span>
        <%= button_to "Cerrar sesión", destroy_user_session_path, method: :delete, class: "btn btn-outline-secondary btn-sm" %>
      <% else %>
        <%= link_to "Iniciar sesión", new_user_session_path, class: "btn btn-outline-primary btn-sm me-2" %>
      <% end %>
    </div>
  </div>
</nav>
```

(The "Importar" link is also gated here since `ImportsController` now requires admin/gerente — this wasn't in the task's file list because it's a two-line addition inside the same file already being edited for the same reason: consistency between what's linked and what's reachable.)

- [ ] **Step 10: Run the users controller test to verify it passes**

```bash
bin/rails test test/controllers/admin/users_controller_test.rb
```
Expected: PASS (all tests).

- [ ] **Step 11: Run the full suite**

```bash
bin/rails test
```
Expected: PASS, 0 failures, 0 errors. If any existing test references `new_user_registration_path`/`/users/sign_up`, it will fail here — fix by removing that assertion (the route is intentionally gone), don't work around it.

- [ ] **Step 12: Manually verify `/users/sign_up` is gone**

```bash
bin/rails routes | grep -i registration
```
Expected: no output (the route no longer exists).

- [ ] **Step 13: Commit**

```bash
git add config/routes.rb app/models/user.rb app/views/devise/registrations app/controllers/admin/users_controller.rb app/views/admin/users app/helpers/application_helper.rb app/views/layouts/_navbar.html.erb test/controllers/admin/users_controller_test.rb
git commit -m "Add admin-only user management, remove self-registration"
```

---

## Post-Plan Manual Verification

- [ ] Sign in as `admin@nalakalu.com`, confirm `/admin/users` works, create a `gerente` and a `visor` test user with a password.
- [ ] Sign in as the new `gerente`: confirm the project index shows ALL projects, confirm editing an unassigned project redirects, confirm creating a new project works and immediately grants edit access on it.
- [ ] From `/admin/users/:id` (as admin), grant the `visor` view access to exactly one project. Sign in as that `visor`: confirm only that one project appears in the index, confirm the project page has no "Editar" button and no bitácora add-form, confirm the historial and bitácora list still render.
- [ ] Confirm `/users/sign_up` returns a 404 (or is simply not linked anywhere) and the navbar no longer shows "Registrarse".
- [ ] Confirm the "Administración"/"Usuarios"/"Importar" navbar links are hidden for `gerente` and `visor`.
