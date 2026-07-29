# Asociaciones entre proyectos Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let projects of one type associate with projects of another type under a configurable label (e.g. "Fase de", "Caso de servicio"), with a fast path to create a new associated project directly from an existing one — extended, per association type, to responsables assigned to the existing project (not just admin/gerente).

**Architecture:** Two new models. `ProjectTypeAssociation` configures which `ProjectType` pairs can associate, under what label, and whether responsables may use the quick-create path. `ProjectAssociation` is the real link between two `Project` records. `ProjectsController#new`/`#create` gain an optional "create already-linked" mode driven by two query/hidden-field params, gated by a new `User#can_create_associated_project?` permission. A new `ProjectAssociationsController` handles linking to an already-existing project. A "Asociaciones" card on `projects#show` ties it all together.

**Tech Stack:** Rails 7.2, Minitest with fixtures, Bootstrap (no new dependency).

## Global Constraints

- Linking to an **existing** project is admin/gerente-only, always — no change there.
- The quick-create path ("+ Nuevo [label]") only ever creates the `from_project` side of an association and links it to an existing `to_project` — never the reverse direction. `ProjectTypeAssociation.where(to_project_type: project.project_type)` is what surfaces the button on a given project's page.
- `User#can_create_associated_project?` is the single gate for the quick-create path: `true` for admin/gerente always; `true` for a `responsable`-role user only when the specific `ProjectTypeAssociation.responsables_can_create?` is set AND they're assigned to (`can_view_project?`) the target project.
- New models need Spanish labels in `config/locales/es.yml` (`activerecord.models` + `activerecord.attributes`), matching the existing pattern for `responsible`/`responsible_type`.
- No soft-delete — deleting a `Project` cascades to its `ProjectAssociation` rows (`dependent: :destroy`) on both sides, matching how the rest of the app handles deletion.

---

### Task 1: `ProjectTypeAssociation` and `ProjectAssociation` models

**Files:**
- Create: `db/migrate/<timestamp>_create_project_type_associations.rb`
- Create: `db/migrate/<timestamp>_create_project_associations.rb`
- Create: `app/models/project_type_association.rb`
- Create: `app/models/project_association.rb`
- Modify: `app/models/project.rb`
- Modify: `config/locales/es.yml`
- Test: `test/models/project_type_association_test.rb`
- Test: `test/models/project_association_test.rb`

**Interfaces:**
- Produces: `ProjectTypeAssociation` (`belongs_to :from_project_type, :to_project_type`, `label`, `responsables_can_create`), `ProjectAssociation` (`belongs_to :from_project, :to_project, :project_type_association`), `Project#outgoing_project_associations`/`#incoming_project_associations`.

- [ ] **Step 1: Write the failing model tests**

```ruby
# test/models/project_type_association_test.rb
require "test_helper"

class ProjectTypeAssociationTest < ActiveSupport::TestCase
  test "valid with from/to project types and a label" do
    other_type = ProjectType.create!(name: "Caso de Servicio", slug: "caso-de-servicio")
    pta = ProjectTypeAssociation.new(from_project_type: other_type, to_project_type: project_types(:instalaciones), label: "Caso de servicio")
    assert pta.valid?
  end

  test "invalid without a label" do
    other_type = ProjectType.create!(name: "Caso de Servicio", slug: "caso-de-servicio")
    pta = ProjectTypeAssociation.new(from_project_type: other_type, to_project_type: project_types(:instalaciones))
    assert_not pta.valid?
  end

  test "responsables_can_create defaults to false" do
    other_type = ProjectType.create!(name: "Caso de Servicio", slug: "caso-de-servicio")
    pta = ProjectTypeAssociation.create!(from_project_type: other_type, to_project_type: project_types(:instalaciones), label: "Caso de servicio")
    assert_equal false, pta.responsables_can_create
  end
end
```

```ruby
# test/models/project_association_test.rb
require "test_helper"

class ProjectAssociationTest < ActiveSupport::TestCase
  setup do
    @caso_type = ProjectType.create!(name: "Caso de Servicio", slug: "caso-de-servicio")
    @association = ProjectTypeAssociation.create!(from_project_type: @caso_type, to_project_type: project_types(:instalaciones), label: "Caso de servicio")
    @instalacion = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    @caso = Project.create!(project_type: @caso_type, name: "Ticket 1", custom_fields: {})
  end

  test "valid when both projects match the association's expected types" do
    pa = ProjectAssociation.new(from_project: @caso, to_project: @instalacion, project_type_association: @association)
    assert pa.valid?
  end

  test "invalid when from_project's type doesn't match" do
    other_caso = Project.create!(project_type: project_types(:instalaciones), name: "Otro", custom_fields: {})
    pa = ProjectAssociation.new(from_project: other_caso, to_project: @instalacion, project_type_association: @association)
    assert_not pa.valid?
  end

  test "invalid when to_project's type doesn't match" do
    other_instalacion = Project.create!(project_type: @caso_type, name: "Otro", custom_fields: {})
    pa = ProjectAssociation.new(from_project: @caso, to_project: other_instalacion, project_type_association: @association)
    assert_not pa.valid?
  end

  test "invalid associating a project with itself" do
    pa = ProjectAssociation.new(from_project: @instalacion, to_project: @instalacion, project_type_association:
      ProjectTypeAssociation.create!(from_project_type: project_types(:instalaciones), to_project_type: project_types(:instalaciones), label: "Relacionado"))
    assert_not pa.valid?
  end

  test "project exposes its outgoing and incoming associations" do
    pa = ProjectAssociation.create!(from_project: @caso, to_project: @instalacion, project_type_association: @association)
    assert_equal [pa], @caso.outgoing_project_associations.to_a
    assert_equal [pa], @instalacion.incoming_project_associations.to_a
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/models/project_type_association_test.rb test/models/project_association_test.rb`
Expected: FAIL — uninitialized constants.

- [ ] **Step 3: Create the migrations**

```ruby
# db/migrate/<timestamp>_create_project_type_associations.rb
class CreateProjectTypeAssociations < ActiveRecord::Migration[7.2]
  def change
    create_table :project_type_associations do |t|
      t.references :from_project_type, null: false, foreign_key: { to_table: :project_types }
      t.references :to_project_type, null: false, foreign_key: { to_table: :project_types }
      t.string :label, null: false
      t.boolean :responsables_can_create, default: false, null: false
      t.timestamps
    end
  end
end
```

```ruby
# db/migrate/<timestamp>_create_project_associations.rb
class CreateProjectAssociations < ActiveRecord::Migration[7.2]
  def change
    create_table :project_associations do |t|
      t.references :from_project, null: false, foreign_key: { to_table: :projects }
      t.references :to_project, null: false, foreign_key: { to_table: :projects }
      t.references :project_type_association, null: false, foreign_key: true
      t.timestamps
      t.index [:from_project_id, :to_project_id, :project_type_association_id], unique: true, name: "index_project_associations_on_triple"
    end
  end
end
```

Run: `bin/rails db:migrate`

- [ ] **Step 4: Create the models**

```ruby
# app/models/project_type_association.rb
class ProjectTypeAssociation < ApplicationRecord
  belongs_to :from_project_type, class_name: "ProjectType"
  belongs_to :to_project_type, class_name: "ProjectType"
  has_many :project_associations, dependent: :destroy

  validates :label, presence: true
end
```

```ruby
# app/models/project_association.rb
class ProjectAssociation < ApplicationRecord
  belongs_to :from_project, class_name: "Project"
  belongs_to :to_project, class_name: "Project"
  belongs_to :project_type_association

  validate :projects_match_association_types
  validate :from_and_to_are_different

  private

  def projects_match_association_types
    return if from_project.nil? || to_project.nil? || project_type_association.nil?
    errors.add(:from_project, "debe ser del tipo esperado por la asociación") unless from_project.project_type_id == project_type_association.from_project_type_id
    errors.add(:to_project, "debe ser del tipo esperado por la asociación") unless to_project.project_type_id == project_type_association.to_project_type_id
  end

  def from_and_to_are_different
    errors.add(:to_project, "un proyecto no puede asociarse consigo mismo") if from_project_id.present? && from_project_id == to_project_id
  end
end
```

- [ ] **Step 5: Wire up `Project`**

In `app/models/project.rb`, add next to `has_many :project_responsibles, dependent: :destroy`:

```ruby
  has_many :outgoing_project_associations, class_name: "ProjectAssociation", foreign_key: :from_project_id, dependent: :destroy
  has_many :incoming_project_associations, class_name: "ProjectAssociation", foreign_key: :to_project_id, dependent: :destroy
```

- [ ] **Step 6: Add Spanish labels**

In `config/locales/es.yml`, under `activerecord.models` (after `project_responsible: "Responsable de proyecto"`):

```yaml
      project_type_association: "Tipo de asociación"
      project_association: "Asociación de proyecto"
```

Under `activerecord.attributes` (after the `responsible:` block):

```yaml
      project_type_association:
        label: "Etiqueta"
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `bin/rails test test/models/project_type_association_test.rb test/models/project_association_test.rb`
Expected: PASS

- [ ] **Step 8: Run the full suite**

Run: `bin/rails test`
Expected: PASS, no regressions.

- [ ] **Step 9: Commit**

```bash
git add db/migrate db/schema.rb app/models/project_type_association.rb app/models/project_association.rb \
  app/models/project.rb config/locales/es.yml test/models/project_type_association_test.rb test/models/project_association_test.rb
git commit -m "Add ProjectTypeAssociation and ProjectAssociation models"
```

---

### Task 2: Admin CRUD for `ProjectTypeAssociation`

**Files:**
- Create: `app/controllers/admin/project_type_associations_controller.rb`
- Create: `app/views/admin/project_type_associations/index.html.erb`
- Create: `app/views/admin/project_type_associations/_form.html.erb`
- Create: `app/views/admin/project_type_associations/new.html.erb`
- Create: `app/views/admin/project_type_associations/edit.html.erb`
- Modify: `config/routes.rb`
- Test: `test/controllers/admin/project_type_associations_controller_test.rb`

**Interfaces:**
- Consumes: `ProjectTypeAssociation` (Task 1).
- Produces: `admin_project_type_associations_path`, `new_admin_project_type_association_path`, `edit_admin_project_type_association_path`, `admin_project_type_association_path`.

This mirrors `Admin::ResponsiblesController` (flat, global, not nested — same pattern).

- [ ] **Step 1: Write the failing tests**

```ruby
# test/controllers/admin/project_type_associations_controller_test.rb
require "test_helper"

class Admin::ProjectTypeAssociationsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:juan) }
  setup { @other_type = ProjectType.create!(name: "Caso de Servicio", slug: "caso-de-servicio") }

  test "index lists project type associations" do
    ProjectTypeAssociation.create!(from_project_type: @other_type, to_project_type: project_types(:instalaciones), label: "Caso de servicio")
    get admin_project_type_associations_path
    assert_response :success
    assert_select "body", /Caso de servicio/
  end

  test "create adds a new project type association" do
    assert_difference("ProjectTypeAssociation.count", 1) do
      post admin_project_type_associations_path, params: {
        project_type_association: {
          from_project_type_id: @other_type.id, to_project_type_id: project_types(:instalaciones).id,
          label: "Caso de servicio", responsables_can_create: "1"
        }
      }
    end
    assert_redirected_to admin_project_type_associations_path
    assert ProjectTypeAssociation.order(:id).last.responsables_can_create
  end

  test "create with blank label re-renders form with error" do
    assert_no_difference("ProjectTypeAssociation.count") do
      post admin_project_type_associations_path, params: {
        project_type_association: { from_project_type_id: @other_type.id, to_project_type_id: project_types(:instalaciones).id, label: "" }
      }
    end
    assert_response :unprocessable_entity
  end

  test "update changes the label and the responsables_can_create flag" do
    pta = ProjectTypeAssociation.create!(from_project_type: @other_type, to_project_type: project_types(:instalaciones), label: "Caso de servicio")
    patch admin_project_type_association_path(pta), params: {
      project_type_association: {
        from_project_type_id: @other_type.id, to_project_type_id: project_types(:instalaciones).id,
        label: "Caso de Servicio Actualizado", responsables_can_create: "1"
      }
    }
    assert_redirected_to admin_project_type_associations_path
    pta.reload
    assert_equal "Caso de Servicio Actualizado", pta.label
    assert pta.responsables_can_create
  end

  test "destroy removes a project type association" do
    pta = ProjectTypeAssociation.create!(from_project_type: @other_type, to_project_type: project_types(:instalaciones), label: "Caso de servicio")
    assert_difference("ProjectTypeAssociation.count", -1) do
      delete admin_project_type_association_path(pta)
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/controllers/admin/project_type_associations_controller_test.rb`
Expected: FAIL — no route/controller yet.

- [ ] **Step 3: Add the route**

In `config/routes.rb`, inside `namespace :admin do`, add next to `resources :responsibles`:

```ruby
    resources :project_type_associations
```

- [ ] **Step 4: Create the controller**

```ruby
# app/controllers/admin/project_type_associations_controller.rb
class Admin::ProjectTypeAssociationsController < Admin::BaseController
  before_action :set_project_type_association, only: [:edit, :update, :destroy]

  def index
    @project_type_associations = ProjectTypeAssociation.all
  end

  def new
    @project_type_association = ProjectTypeAssociation.new
  end

  def create
    @project_type_association = ProjectTypeAssociation.new(project_type_association_params)
    if @project_type_association.save
      redirect_to admin_project_type_associations_path
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @project_type_association.update(project_type_association_params)
      redirect_to admin_project_type_associations_path
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @project_type_association.destroy
    redirect_to admin_project_type_associations_path
  end

  private

  def set_project_type_association
    @project_type_association = ProjectTypeAssociation.find(params[:id])
  end

  def project_type_association_params
    params.require(:project_type_association).permit(:from_project_type_id, :to_project_type_id, :label, :responsables_can_create)
  end
end
```

- [ ] **Step 5: Create the views**

```erb
<%# app/views/admin/project_type_associations/index.html.erb %>
<%= panel_card("Tipos de asociación") do %>
  <%= link_to "Nuevo tipo de asociación", new_admin_project_type_association_path, class: "btn btn-primary mb-3" %>
  <ul class="list-group">
    <% @project_type_associations.each do |pta| %>
      <li class="list-group-item d-flex justify-content-between align-items-center">
        <span><%= pta.from_project_type.name %> → <%= pta.label %> → <%= pta.to_project_type.name %></span>
        <span>
          <%= link_to "Editar", edit_admin_project_type_association_path(pta), class: "btn btn-outline-secondary btn-sm" %>
          <%= button_to "Borrar", admin_project_type_association_path(pta), method: :delete,
                class: "btn btn-outline-danger btn-sm", form: { style: "display:inline-block", onsubmit: "return confirm('¿Eliminar tipo de asociación?')" } %>
        </span>
      </li>
    <% end %>
  </ul>
<% end %>
```

```erb
<%# app/views/admin/project_type_associations/_form.html.erb %>
<%= panel_card(project_type_association.persisted? ? "Editar tipo de asociación" : "Nuevo tipo de asociación") do %>
  <%= form_with model: [:admin, project_type_association] do |form| %>
    <% if project_type_association.errors.any? %>
      <div class="alert alert-danger">
        <ul class="mb-0">
          <% project_type_association.errors.full_messages.each do |message| %>
            <li><%= message %></li>
          <% end %>
        </ul>
      </div>
    <% end %>

    <div class="mb-3">
      <%= form.label :from_project_type_id, "Tipo de origen", class: "form-label" %>
      <%= form.collection_select :from_project_type_id, ProjectType.order(:name), :id, :name, {}, class: "form-select" %>
    </div>

    <div class="mb-3">
      <%= form.label :to_project_type_id, "Tipo de destino", class: "form-label" %>
      <%= form.collection_select :to_project_type_id, ProjectType.order(:name), :id, :name, {}, class: "form-select" %>
    </div>

    <div class="mb-3">
      <%= form.label :label, "Etiqueta", class: "form-label" %>
      <%= form.text_field :label, class: "form-control" %>
    </div>

    <div class="form-check mb-3">
      <%= form.check_box :responsables_can_create, class: "form-check-input" %>
      <%= form.label :responsables_can_create, "Responsables pueden crear", class: "form-check-label" %>
    </div>

    <%= form.submit class: "btn btn-primary" %>
  <% end %>
<% end %>
```

```erb
<%# app/views/admin/project_type_associations/new.html.erb %>
<%= render "form", project_type_association: @project_type_association %>
```

```erb
<%# app/views/admin/project_type_associations/edit.html.erb %>
<%= render "form", project_type_association: @project_type_association %>
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bin/rails test test/controllers/admin/project_type_associations_controller_test.rb`
Expected: PASS

- [ ] **Step 7: Run the full suite**

Run: `bin/rails test`
Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add config/routes.rb app/controllers/admin/project_type_associations_controller.rb \
  app/views/admin/project_type_associations test/controllers/admin/project_type_associations_controller_test.rb
git commit -m "Add admin CRUD for project type associations"
```

---

### Task 3: Permission + quick-create path on `ProjectsController`

**Files:**
- Modify: `app/models/user.rb`
- Modify: `app/controllers/projects_controller.rb`
- Modify: `app/views/projects/_form.html.erb`
- Test: `test/models/user_test.rb`
- Test: `test/controllers/projects_controller_test.rb`

**Interfaces:**
- Consumes: `ProjectTypeAssociation`, `ProjectAssociation` (Task 1).
- Produces: `User#can_create_associated_project?(association, target_project)`, `ProjectsController#new`'s `@project_type_association_id`/`@associate_with_project_id`.

- [ ] **Step 1: Write the failing tests**

Add to `test/models/user_test.rb`, inside `class UserTest`:

```ruby
  test "can_create_associated_project? is always true for admin and gerente" do
    other_type = ProjectType.create!(name: "Caso de Servicio", slug: "caso-de-servicio")
    association = ProjectTypeAssociation.create!(from_project_type: other_type, to_project_type: project_types(:instalaciones), label: "Caso de servicio")
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})

    assert users(:juan).can_create_associated_project?(association, project)
    assert users(:carla).can_create_associated_project?(association, project)
  end

  test "can_create_associated_project? is true for an assigned responsable only when the association allows it" do
    other_type = ProjectType.create!(name: "Caso de Servicio", slug: "caso-de-servicio")
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    responsable = users(:pedro)
    ProjectResponsible.create!(project: project, responsible: responsable.responsible, responsible_type: responsible_types(:instalador))

    allowed = ProjectTypeAssociation.create!(from_project_type: other_type, to_project_type: project_types(:instalaciones), label: "Caso de servicio", responsables_can_create: true)
    assert responsable.can_create_associated_project?(allowed, project)

    not_allowed = ProjectTypeAssociation.create!(from_project_type: other_type, to_project_type: project_types(:instalaciones), label: "Fase de", responsables_can_create: false)
    assert_not responsable.can_create_associated_project?(not_allowed, project)
  end

  test "can_create_associated_project? is false for a responsable not assigned to the target project" do
    other_type = ProjectType.create!(name: "Caso de Servicio", slug: "caso-de-servicio")
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    association = ProjectTypeAssociation.create!(from_project_type: other_type, to_project_type: project_types(:instalaciones), label: "Caso de servicio", responsables_can_create: true)

    assert_not users(:pedro).can_create_associated_project?(association, project)
  end
```

Add to `test/controllers/projects_controller_test.rb`:

```ruby
  test "new/create is reachable by an assigned responsable when the association allows it, and links to the target project" do
    other_type = ProjectType.create!(name: "Caso de Servicio", slug: "caso-de-servicio")
    target = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    responsable = users(:pedro)
    ProjectResponsible.create!(project: target, responsible: responsable.responsible, responsible_type: responsible_types(:instalador))
    association = ProjectTypeAssociation.create!(from_project_type: other_type, to_project_type: project_types(:instalaciones), label: "Caso de servicio", responsables_can_create: true)
    sign_in responsable

    get new_project_path(project_type_id: other_type.id, project_type_association_id: association.id, associate_with_project_id: target.id)
    assert_response :success

    assert_difference("Project.count", 1) do
      post projects_path, params: {
        project: { project_type_id: other_type.id, name: "Ticket 1", custom_fields: {} },
        project_type_association_id: association.id, associate_with_project_id: target.id
      }
    end

    created = Project.order(:id).last
    assert_redirected_to project_path(target)
    assert ProjectAssociation.exists?(from_project: created, to_project: target, project_type_association: association)
  end

  test "new/create rejects a responsable when the association doesn't allow responsables to create" do
    other_type = ProjectType.create!(name: "Caso de Servicio", slug: "caso-de-servicio")
    target = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    responsable = users(:pedro)
    ProjectResponsible.create!(project: target, responsible: responsable.responsible, responsible_type: responsible_types(:instalador))
    association = ProjectTypeAssociation.create!(from_project_type: other_type, to_project_type: project_types(:instalaciones), label: "Caso de servicio")
    sign_in responsable

    get new_project_path(project_type_id: other_type.id, project_type_association_id: association.id, associate_with_project_id: target.id)
    assert_redirected_to projects_path
  end

  test "create as admin without association context still creates a standalone project" do
    assert_difference("Project.count", 1) do
      post projects_path, params: {
        project: { project_type_id: project_types(:instalaciones).id, name: "Torre Sur", custom_fields: {} }
      }
    end
    created = Project.order(:id).last
    assert_redirected_to project_path(created)
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/models/user_test.rb test/controllers/projects_controller_test.rb -n "/can_create_associated_project|association allows|association doesn't allow|without association context/"`
Expected: FAIL — `can_create_associated_project?` doesn't exist yet; `new`/`create` don't accept the association params yet.

- [ ] **Step 3: Add `User#can_create_associated_project?`**

In `app/models/user.rb`, add after `editable_project_stage_ids`:

```ruby
  def can_create_associated_project?(association, target_project)
    return true if admin? || gerente?
    association.responsables_can_create? && responsable? && can_view_project?(target_project)
  end
```

- [ ] **Step 4: Update `ProjectsController`**

Replace `before_action :require_admin_or_gerente!, only: [:new, :create, :bulk_assign_responsible]` with:

```ruby
  before_action :require_admin_or_gerente!, only: [:bulk_assign_responsible]
  before_action :authorize_new!, only: [:new, :create]
```

Add this private method next to `authorize_update!`:

```ruby
  def authorize_new!
    return if current_user.admin? || current_user.gerente?
    association = ProjectTypeAssociation.find_by(id: params[:project_type_association_id])
    target_project = Project.find_by(id: params[:associate_with_project_id])
    return if association && target_project && current_user.can_create_associated_project?(association, target_project)
    redirect_to projects_path, alert: "No tenés permiso para crear proyectos."
  end
```

Replace `new`:

```ruby
  def new
    @project_type = ProjectType.find(params[:project_type_id]) if params[:project_type_id]
    @project = Project.new(project_type: @project_type)
    @project_type_association_id = params[:project_type_association_id]
    @associate_with_project_id = params[:associate_with_project_id]
  end
```

Replace `create`:

```ruby
  def create
    @project = Project.new(project_params)
    @project_type = @project.project_type
    if @project.save
      ProjectAccess.create!(user: current_user, project: @project, can_edit: true) if current_user.gerente?
      if params[:project_type_association_id].present? && params[:associate_with_project_id].present?
        ProjectAssociation.create!(
          from_project: @project, to_project_id: params[:associate_with_project_id],
          project_type_association_id: params[:project_type_association_id]
        )
        redirect_to project_path(params[:associate_with_project_id])
      else
        redirect_to project_path(@project)
      end
    else
      @project_type_association_id = params[:project_type_association_id]
      @associate_with_project_id = params[:associate_with_project_id]
      render :new, status: :unprocessable_entity
    end
  end
```

(The `else` branch re-populates the two ivars so the re-rendered `new` template keeps the hidden fields on a validation-error redisplay — otherwise a failed submission would silently drop the association context.)

- [ ] **Step 5: Carry the params through the form**

In `app/views/projects/_form.html.erb`, add right after `<%= form.hidden_field :project_type_id, value: project_type.id %>`:

```erb
  <%= hidden_field_tag :project_type_association_id, @project_type_association_id if @project_type_association_id.present? %>
  <%= hidden_field_tag :associate_with_project_id, @associate_with_project_id if @associate_with_project_id.present? %>
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bin/rails test test/models/user_test.rb test/controllers/projects_controller_test.rb`
Expected: PASS

- [ ] **Step 7: Run the full suite**

Run: `bin/rails test`
Expected: PASS — every existing test that creates a project via `new`/`create` as admin/gerente without association params must still work unchanged (the new `authorize_new!` short-circuits to the old behavior for them).

- [ ] **Step 8: Commit**

```bash
git add app/models/user.rb app/controllers/projects_controller.rb app/views/projects/_form.html.erb \
  test/models/user_test.rb test/controllers/projects_controller_test.rb
git commit -m "Let an assigned responsable create an associated project when allowed"
```

---

### Task 4: Link to an existing project + "Asociaciones" card

**Files:**
- Create: `app/controllers/project_associations_controller.rb`
- Modify: `config/routes.rb`
- Modify: `app/views/projects/show.html.erb`
- Test: `test/controllers/project_associations_controller_test.rb`

**Interfaces:**
- Consumes: `ProjectTypeAssociation`, `ProjectAssociation` (Task 1), `User#can_create_associated_project?` (Task 3).
- Produces: `project_project_associations_path(project)`, `project_project_association_path(project, project_association)`.

- [ ] **Step 1: Write the failing tests**

```ruby
# test/controllers/project_associations_controller_test.rb
require "test_helper"

class ProjectAssociationsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:juan) }
  setup do
    @caso_type = ProjectType.create!(name: "Caso de Servicio", slug: "caso-de-servicio")
    @association = ProjectTypeAssociation.create!(from_project_type: @caso_type, to_project_type: project_types(:instalaciones), label: "Caso de servicio")
    @instalacion = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    @caso = Project.create!(project_type: @caso_type, name: "Ticket 1", custom_fields: {})
  end

  test "create links an existing caso to an instalacion when starting from the instalacion" do
    assert_difference("ProjectAssociation.count", 1) do
      post project_project_associations_path(@instalacion), params: {
        project_association: { project_type_association_id: @association.id, other_project_id: @caso.id }
      }
    end
    assert_redirected_to project_path(@instalacion)
    pa = ProjectAssociation.order(:id).last
    assert_equal @caso, pa.from_project
    assert_equal @instalacion, pa.to_project
  end

  test "create links starting from the caso, resolving direction automatically" do
    assert_difference("ProjectAssociation.count", 1) do
      post project_project_associations_path(@caso), params: {
        project_association: { project_type_association_id: @association.id, other_project_id: @instalacion.id }
      }
    end
    pa = ProjectAssociation.order(:id).last
    assert_equal @caso, pa.from_project
    assert_equal @instalacion, pa.to_project
  end

  test "create with a mismatched project renders an error and creates nothing" do
    other_instalacion = Project.create!(project_type: project_types(:instalaciones), name: "Otra", custom_fields: {})
    assert_no_difference("ProjectAssociation.count") do
      post project_project_associations_path(@instalacion), params: {
        project_association: { project_type_association_id: @association.id, other_project_id: other_instalacion.id }
      }
    end
    assert_redirected_to project_path(@instalacion)
  end

  test "destroy removes an association" do
    pa = ProjectAssociation.create!(from_project: @caso, to_project: @instalacion, project_type_association: @association)
    assert_difference("ProjectAssociation.count", -1) do
      delete project_project_association_path(@instalacion, pa)
    end
  end

  test "visor without edit access cannot create an association" do
    sign_in users(:maria)
    assert_no_difference("ProjectAssociation.count") do
      post project_project_associations_path(@instalacion), params: {
        project_association: { project_type_association_id: @association.id, other_project_id: @caso.id }
      }
    end
    assert_redirected_to root_path
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/controllers/project_associations_controller_test.rb`
Expected: FAIL — no route/controller yet.

- [ ] **Step 3: Add the route**

In `config/routes.rb`, inside `resources :projects do`, add next to `resources :project_responsibles, only: [:create, :destroy]`:

```ruby
    resources :project_associations, only: [:create, :destroy]
```

- [ ] **Step 4: Create the controller**

```ruby
# app/controllers/project_associations_controller.rb
class ProjectAssociationsController < ApplicationController
  before_action :set_project
  before_action :authorize_edit!

  def create
    association = ProjectTypeAssociation.find(params[:project_association][:project_type_association_id])
    other_id = params[:project_association][:other_project_id]

    pa = if @project.project_type_id == association.from_project_type_id
      ProjectAssociation.new(from_project: @project, to_project_id: other_id, project_type_association: association)
    else
      ProjectAssociation.new(from_project_id: other_id, to_project: @project, project_type_association: association)
    end

    if pa.save
      redirect_to project_path(@project)
    else
      redirect_to project_path(@project), alert: pa.errors.full_messages.to_sentence
    end
  end

  def destroy
    pa = ProjectAssociation.find(params[:id])
    pa.destroy if pa.from_project_id == @project.id || pa.to_project_id == @project.id
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
end
```

- [ ] **Step 5: Add the "Asociaciones" card to `projects/show.html.erb`**

Read the current file first — add this card right after the "Responsables" card (before "Bitácora"):

```erb
<% if current_user.can_edit_project?(@project) || ProjectTypeAssociation.where(to_project_type: @project.project_type, responsables_can_create: true).any? { |a| current_user.can_create_associated_project?(a, @project) } %>
  <div class="card mb-4">
    <div class="card-header">Asociaciones</div>
    <div class="card-body">
      <ul class="list-group list-group-flush mb-3">
        <% @project.outgoing_project_associations.includes(:to_project, :project_type_association).each do |pa| %>
          <li class="list-group-item d-flex justify-content-between align-items-center">
            <span>Este proyecto es <strong><%= pa.project_type_association.label %></strong> de <%= link_to pa.to_project.name, project_path(pa.to_project) %></span>
            <% if current_user.can_edit_project?(@project) %>
              <%= button_to "Quitar", project_project_association_path(@project, pa), method: :delete, class: "btn btn-outline-danger btn-sm" %>
            <% end %>
          </li>
        <% end %>
        <% @project.incoming_project_associations.includes(:from_project, :project_type_association).each do |pa| %>
          <li class="list-group-item d-flex justify-content-between align-items-center">
            <span><%= link_to pa.from_project.name, project_path(pa.from_project) %> es <strong><%= pa.project_type_association.label %></strong> de este proyecto</span>
            <% if current_user.can_edit_project?(@project) %>
              <%= button_to "Quitar", project_project_association_path(@project, pa), method: :delete, class: "btn btn-outline-danger btn-sm" %>
            <% end %>
          </li>
        <% end %>
      </ul>

      <% if current_user.can_edit_project?(@project) %>
        <%# ponytail: "Proyecto" lista todos los proyectos sin acotar por tipo vía JS —
            se valida del lado del servidor. Upgrade a selector dependiente con JS si la
            lista de proyectos crece mucho. %>
        <%= form_with url: project_project_associations_path(@project), method: :post, scope: :project_association, class: "row g-2 mb-3" do |f| %>
          <div class="col-auto">
            <%= f.collection_select :project_type_association_id,
                  ProjectTypeAssociation.where(from_project_type: @project.project_type).or(ProjectTypeAssociation.where(to_project_type: @project.project_type)),
                  :id, :label, { include_blank: "Tipo de asociación" }, class: "form-select" %>
          </div>
          <div class="col-auto">
            <%= f.collection_select :other_project_id, Project.where.not(id: @project.id).order(:name), :id, :name, { include_blank: "Proyecto" }, class: "form-select" %>
          </div>
          <div class="col-auto">
            <%= f.submit "Vincular", class: "btn btn-primary" %>
          </div>
        <% end %>
      <% end %>

      <% ProjectTypeAssociation.where(to_project_type: @project.project_type).each do |association| %>
        <% if current_user.can_create_associated_project?(association, @project) %>
          <%= link_to "+ Nuevo #{association.label}",
                new_project_path(project_type_id: association.from_project_type_id, project_type_association_id: association.id, associate_with_project_id: @project.id),
                class: "btn btn-outline-primary btn-sm" %>
        <% end %>
      <% end %>
    </div>
  </div>
<% end %>
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bin/rails test test/controllers/project_associations_controller_test.rb`
Expected: PASS

- [ ] **Step 7: Run the full suite**

Run: `bin/rails test`
Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add config/routes.rb app/controllers/project_associations_controller.rb app/views/projects/show.html.erb \
  test/controllers/project_associations_controller_test.rb
git commit -m "Let admin/gerente link an existing project and show the Asociaciones card"
```
