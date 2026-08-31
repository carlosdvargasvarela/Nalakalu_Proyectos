# Eventos de proyecto en el Gantt Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users record events (reuniones, hitos, entregas, etc.), optionally tied to a project's subproceso (`ProjectStage`), and see them as colored points on the project's Gantt chart plus a listing table.

**Architecture:** Two new tables (`event_types`, admin-configurable per `ProjectType`; `events`, belonging to a `Project` and optionally a `ProjectStage`), a new admin CRUD for `event_types` mirroring `StageTemplate`'s, a new `EventsController` mirroring `ProjectResponsiblesController`'s (plus `update`), and a JS extension to the existing `gantt_stage_editor_controller.js` that overlays diamond markers on stage bars (computed from the already-rendered SVG bar geometry, not frappe-gantt internals) and renders stage-less events as native frappe-gantt `milestone` tasks.

**Tech Stack:** Rails 7.2, Minitest + fixtures, Stimulus, frappe-gantt 1.2.2 (CDN, already vendored via `<script>` tag), Bootstrap 5 (bundled, `bootstrap.Modal` already used in `help_controller.js`).

**Spec:** `docs/superpowers/specs/2026-08-31-eventos-proyecto-gantt-design.md`

## Global Constraints

- Rails migration version must be `ActiveRecord::Migration[7.2]` — this app only supports up to 7.2 (see `db/migrate/20260831160000_add_icon_to_project_types.rb`).
- Color columns validate `/\A#[0-9a-fA-F]{6}\z/` with message `"debe ser un color hexadecimal (ej. #6c757d)"` (same as `StageTemplate`/`LogEntryType`).
- Admin CRUD lives under `Admin::BaseController` (`before_action :require_admin!`).
- Project-scoped mutation endpoints authorize via `current_user.can_edit_project?(@project)`, redirecting to `root_path` with alert `"No tenés permiso para hacer eso."` on failure (same as `ProjectResponsiblesController`).
- No RSpec, no Capybara helpers beyond what's already used — Minitest + fixtures, `ActionDispatch::SystemTestCase` (already configured in `test/application_system_test_case.rb`) for the one browser-rendered check.
- Do not touch `_project_type_section.html.erb` (the type-listing Gantt) — out of scope per spec.

---

### Task 1: `EventType` model, migration, and validations

**Files:**
- Create: `db/migrate/20260831161000_create_event_types.rb`
- Create: `app/models/event_type.rb`
- Modify: `app/models/project_type.rb` (add `has_many :event_types`)
- Test: `test/models/event_type_test.rb`
- Test fixtures: `test/fixtures/event_types.yml`

**Interfaces:**
- Produces: `EventType` with columns `project_type_id`, `name`, `color` (string, default `"#6c757d"`), `icon` (string, default `"bi-calendar-event"`), `position` (integer, default 0). `belongs_to :project_type`. `ProjectType#event_types` ordered by `:position`.

- [ ] **Step 1: Write the migration**

```ruby
# db/migrate/20260831161000_create_event_types.rb
class CreateEventTypes < ActiveRecord::Migration[7.2]
  def change
    create_table :event_types do |t|
      t.references :project_type, null: false, foreign_key: true
      t.string :name, null: false
      t.string :color, null: false, default: "#6c757d"
      t.string :icon, null: false, default: "bi-calendar-event"
      t.integer :position, null: false, default: 0

      t.timestamps
    end
  end
end
```

- [ ] **Step 2: Run the migration**

Run: `bin/rails db:migrate`
Expected: `== 20260831161000 CreateEventTypes: migrated` and `db/schema.rb` now has a `event_types` table.

- [ ] **Step 3: Write the failing model test**

```ruby
# test/models/event_type_test.rb
require "test_helper"

class EventTypeTest < ActiveSupport::TestCase
  test "valid with name" do
    event_type = EventType.new(project_type: project_types(:instalaciones), name: "Reunión")
    assert event_type.valid?
  end

  test "invalid without name" do
    event_type = EventType.new(project_type: project_types(:instalaciones))
    assert_not event_type.valid?
  end

  test "valid with default color and icon" do
    event_type = EventType.new(project_type: project_types(:instalaciones), name: "Reunión")
    assert event_type.valid?
    assert_equal "#6c757d", event_type.color
    assert_equal "bi-calendar-event", event_type.icon
  end

  test "invalid with a malformed color" do
    event_type = EventType.new(project_type: project_types(:instalaciones), name: "Reunión", color: "blue")
    assert_not event_type.valid?
  end

  test "project_type has_many event_types ordered by position" do
    ordered = project_types(:instalaciones).event_types.map(&:name)
    assert_equal ["Reunión de obra", "Entrega final"], ordered
  end
end
```

- [ ] **Step 4: Run test to verify it fails**

Run: `bin/rails test test/models/event_type_test.rb`
Expected: FAIL — `uninitialized constant EventType`

- [ ] **Step 5: Write the model**

```ruby
# app/models/event_type.rb
class EventType < ApplicationRecord
  belongs_to :project_type

  validates :name, presence: true
  validates :color, format: { with: /\A#[0-9a-fA-F]{6}\z/, message: "debe ser un color hexadecimal (ej. #6c757d)" }
end
```

Modify `app/models/project_type.rb` — add this line next to `has_many :stage_templates`:

```ruby
  has_many :event_types, -> { order(:position) }, dependent: :destroy
```

- [ ] **Step 6: Add fixtures**

```yaml
# test/fixtures/event_types.yml
reunion_obra:
  project_type_id: <%= ActiveRecord::FixtureSet.identify(:instalaciones) %>
  name: Reunión de obra
  position: 1
  created_at: <%= Time.current %>
  updated_at: <%= Time.current %>

entrega_final:
  project_type_id: <%= ActiveRecord::FixtureSet.identify(:instalaciones) %>
  name: Entrega final
  position: 2
  created_at: <%= Time.current %>
  updated_at: <%= Time.current %>
```

- [ ] **Step 7: Run test to verify it passes**

Run: `bin/rails test test/models/event_type_test.rb`
Expected: PASS (5 runs, 0 failures)

- [ ] **Step 8: Commit**

```bash
git add db/migrate/20260831161000_create_event_types.rb db/schema.rb app/models/event_type.rb app/models/project_type.rb test/models/event_type_test.rb test/fixtures/event_types.yml
git commit -m "Agregar modelo EventType"
```

---

### Task 2: `Event` model, migration, and validations

**Files:**
- Create: `db/migrate/20260831162000_create_events.rb`
- Create: `app/models/event.rb`
- Modify: `app/models/project.rb` (add `has_many :events`)
- Modify: `app/models/project_stage.rb` (add `has_many :events`)
- Modify: `app/models/responsible.rb` (add `has_many :events`)
- Test: `test/models/event_test.rb`

**Interfaces:**
- Consumes: `EventType` from Task 1 (`event_type.project_type_id`).
- Produces: `Event` with `project_id`, `project_stage_id` (optional), `event_type_id`, `responsible_id` (optional), `title`, `event_date`, `event_time` (optional), `notes` (optional), `status` (default `"pendiente"`). `Event#project_wide?` mirrors `ProjectResponsible#project_wide?`.

- [ ] **Step 1: Write the migration**

```ruby
# db/migrate/20260831162000_create_events.rb
class CreateEvents < ActiveRecord::Migration[7.2]
  def change
    create_table :events do |t|
      t.references :project, null: false, foreign_key: true
      t.references :project_stage, foreign_key: true
      t.references :event_type, null: false, foreign_key: true
      t.references :responsible, foreign_key: true
      t.string :title, null: false
      t.date :event_date, null: false
      t.time :event_time
      t.text :notes
      t.string :status, null: false, default: "pendiente"

      t.timestamps
    end
  end
end
```

- [ ] **Step 2: Run the migration**

Run: `bin/rails db:migrate`
Expected: `== 20260831162000 CreateEvents: migrated` and `db/schema.rb` now has an `events` table.

- [ ] **Step 3: Write the failing model test**

```ruby
# test/models/event_test.rb
require "test_helper"

class EventTest < ActiveSupport::TestCase
  setup do
    @project_type = project_types(:instalaciones)
    @event_type = event_types(:reunion_obra)
    @project = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: {})
  end

  test "valid with project, event_type, title and event_date" do
    event = Event.new(project: @project, event_type: @event_type, title: "Kickoff", event_date: Date.current)
    assert event.valid?
  end

  test "invalid without title" do
    event = Event.new(project: @project, event_type: @event_type, event_date: Date.current)
    assert_not event.valid?
  end

  test "invalid without event_date" do
    event = Event.new(project: @project, event_type: @event_type, title: "Kickoff")
    assert_not event.valid?
  end

  test "project_wide? is true with no project_stage" do
    event = Event.new(project: @project, event_type: @event_type, title: "Kickoff", event_date: Date.current)
    assert event.project_wide?
  end

  test "project_wide? is false when scoped to a stage" do
    stage = @project.project_stages.first
    event = Event.new(project: @project, event_type: @event_type, title: "Kickoff", event_date: Date.current, project_stage: stage)
    assert_not event.project_wide?
  end

  test "invalid when project_stage belongs to a different project" do
    other_project = Project.create!(project_type: @project_type, name: "Torre Sur", custom_fields: {})
    event = Event.new(
      project: @project, event_type: @event_type, title: "Kickoff", event_date: Date.current,
      project_stage: other_project.project_stages.first
    )
    assert_not event.valid?
  end

  test "invalid when event_type belongs to a different project_type" do
    other_type = ProjectType.create!(name: "Mantenimiento", slug: "mantenimiento")
    other_event_type = EventType.create!(project_type: other_type, name: "Visita")
    event = Event.new(project: @project, event_type: other_event_type, title: "Kickoff", event_date: Date.current)
    assert_not event.valid?
  end

  test "defaults status to pendiente" do
    event = Event.create!(project: @project, event_type: @event_type, title: "Kickoff", event_date: Date.current)
    assert_equal "pendiente", event.status
  end

  test "deleting a project_stage nullifies its events instead of destroying them" do
    stage = @project.project_stages.first
    event = Event.create!(project: @project, event_type: @event_type, title: "Kickoff", event_date: Date.current, project_stage: stage)
    stage.destroy
    assert event.reload.project_stage_id.nil?
  end
end
```

- [ ] **Step 4: Run test to verify it fails**

Run: `bin/rails test test/models/event_test.rb`
Expected: FAIL — `uninitialized constant Event`

- [ ] **Step 5: Write the model**

```ruby
# app/models/event.rb
class Event < ApplicationRecord
  belongs_to :project
  belongs_to :project_stage, optional: true
  belongs_to :event_type
  belongs_to :responsible, optional: true

  validates :title, presence: true
  validates :event_date, presence: true
  validates :status, inclusion: { in: %w[pendiente realizado] }
  validate :project_stage_belongs_to_project
  validate :event_type_belongs_to_project_type

  def project_wide?
    project_stage_id.nil?
  end

  private

  def project_stage_belongs_to_project
    return if project_stage.nil? || project.nil?
    errors.add(:project_stage, "debe pertenecer al mismo proyecto") unless project_stage.project_id == project.id
  end

  def event_type_belongs_to_project_type
    return if event_type.nil? || project.nil?
    errors.add(:event_type, "debe pertenecer al tipo de este proyecto") unless event_type.project_type_id == project.project_type_id
  end
end
```

Modify `app/models/project.rb` — add next to `has_many :project_responsibles`:

```ruby
  has_many :events, dependent: :destroy
```

Modify `app/models/project_stage.rb` — add next to `has_many :project_responsibles`:

```ruby
  has_many :events, dependent: :nullify
```

Modify `app/models/responsible.rb` — add next to `has_many :project_responsibles`:

```ruby
  has_many :events, dependent: :nullify
```

- [ ] **Step 6: Run test to verify it passes**

Run: `bin/rails test test/models/event_test.rb`
Expected: PASS (9 runs, 0 failures)

- [ ] **Step 7: Commit**

```bash
git add db/migrate/20260831162000_create_events.rb db/schema.rb app/models/event.rb app/models/project.rb app/models/project_stage.rb app/models/responsible.rb test/models/event_test.rb
git commit -m "Agregar modelo Event"
```

---

### Task 3: Admin CRUD for `event_types`

**Files:**
- Create: `app/controllers/admin/event_types_controller.rb`
- Create: `app/views/admin/event_types/_form.html.erb`
- Create: `app/views/admin/event_types/new.html.erb`
- Create: `app/views/admin/event_types/edit.html.erb`
- Modify: `config/routes.rb`
- Test: `test/controllers/admin/event_types_controller_test.rb`

**Interfaces:**
- Consumes: `EventType`, `ProjectType#event_types` from Task 1.
- Produces: routes `admin_project_type_event_types_path`, `new_admin_project_type_event_type_path`, `edit_admin_project_type_event_type_path`, `admin_project_type_event_type_path`, `reorder_admin_project_type_event_types_path`.

- [ ] **Step 1: Add routes**

Modify `config/routes.rb` — inside the `resources :project_types do ... end` block in the `admin` namespace, add next to `resources :stage_templates`:

```ruby
      resources :event_types, except: [:index, :show] do
        patch :reorder, on: :collection
      end
```

- [ ] **Step 2: Write the failing controller test**

```ruby
# test/controllers/admin/event_types_controller_test.rb
require "test_helper"

class Admin::EventTypesControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:juan) }
  setup { @project_type = project_types(:instalaciones) }

  test "create adds an event type to the project type" do
    assert_difference("@project_type.event_types.count", 1) do
      post admin_project_type_event_types_path(@project_type), params: {
        event_type: { name: "Visita técnica", position: 3, color: "#123abc", icon: "bi-tools" }
      }
    end
    assert_redirected_to admin_project_type_path(@project_type)
  end

  test "create with blank name re-renders form with error" do
    assert_no_difference("@project_type.event_types.count") do
      post admin_project_type_event_types_path(@project_type), params: {
        event_type: { name: "", position: 3 }
      }
    end
    assert_response :unprocessable_entity
  end

  test "update saves the color and icon" do
    event_type = event_types(:reunion_obra)
    patch admin_project_type_event_type_path(@project_type, event_type), params: {
      event_type: { name: event_type.name, position: event_type.position, color: "#f60404", icon: "bi-flag" }
    }
    assert_redirected_to admin_project_type_path(@project_type)
    assert_equal "#f60404", event_type.reload.color
    assert_equal "bi-flag", event_type.reload.icon
  end

  test "destroy removes an event type with no events" do
    event_type = event_types(:reunion_obra)
    assert_difference("@project_type.event_types.count", -1) do
      delete admin_project_type_event_type_path(@project_type, event_type)
    end
  end

  test "destroy with existing events redirects with an error instead of destroying" do
    project = Project.create!(project_type: @project_type, name: "Torre Norte", custom_fields: {})
    event_type = event_types(:reunion_obra)
    Event.create!(project: project, event_type: event_type, title: "Kickoff", event_date: Date.current)

    assert_no_difference("@project_type.event_types.count") do
      delete admin_project_type_event_type_path(@project_type, event_type)
    end
    assert_redirected_to admin_project_type_path(@project_type)
  end

  test "reorder updates position according to the submitted id order" do
    reunion = event_types(:reunion_obra)
    entrega = event_types(:entrega_final)

    patch reorder_admin_project_type_event_types_path(@project_type), params: { ids: [entrega.id, reunion.id] }, as: :json
    assert_response :success

    assert_equal 0, entrega.reload.position
    assert_equal 1, reunion.reload.position
  end

  test "new and edit show the submit button in Spanish" do
    get new_admin_project_type_event_type_path(@project_type)
    assert_response :success
    assert_select "input[value=?]", "Crear Tipo De Evento"

    get edit_admin_project_type_event_type_path(@project_type, event_types(:reunion_obra))
    assert_response :success
    assert_select "input[value=?]", "Actualizar Tipo De Evento"
  end
end
```

- [ ] **Step 3: Run test to verify it fails**

Run: `bin/rails test test/controllers/admin/event_types_controller_test.rb`
Expected: FAIL — routing error (`admin_project_type_event_types_path` undefined)

- [ ] **Step 4: Write the controller**

```ruby
# app/controllers/admin/event_types_controller.rb
class Admin::EventTypesController < Admin::BaseController
  before_action :set_project_type
  before_action :set_event_type, only: [:edit, :update, :destroy]

  def new
    @event_type = @project_type.event_types.new
  end

  def create
    @event_type = @project_type.event_types.new(event_type_params)
    if @event_type.save
      redirect_to admin_project_type_path(@project_type)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @event_type.update(event_type_params)
      redirect_to admin_project_type_path(@project_type)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @event_type.destroy
      redirect_to admin_project_type_path(@project_type)
    else
      redirect_to admin_project_type_path(@project_type), alert: @event_type.errors.full_messages.to_sentence
    end
  end

  def reorder
    Array(params[:ids]).each_with_index do |id, index|
      @project_type.event_types.where(id: id).update_all(position: index)
    end
    head :ok
  end

  private

  def set_project_type
    @project_type = ProjectType.find(params[:project_type_id])
  end

  def set_event_type
    @event_type = @project_type.event_types.find(params[:id])
  end

  def event_type_params
    params.require(:event_type).permit(:name, :position, :color, :icon)
  end
end
```

Note: `EventType` has no `has_many :events` yet with `dependent: :restrict_with_error` — add it now since the destroy action and its test depend on it:

Modify `app/models/event_type.rb`:

```ruby
class EventType < ApplicationRecord
  belongs_to :project_type
  has_many :events, dependent: :restrict_with_error

  validates :name, presence: true
  validates :color, format: { with: /\A#[0-9a-fA-F]{6}\z/, message: "debe ser un color hexadecimal (ej. #6c757d)" }
end
```

- [ ] **Step 5: Write the views**

```erb
<%# app/views/admin/event_types/new.html.erb %>
<%= render "form", project_type: @project_type, event_type: @event_type %>
```

```erb
<%# app/views/admin/event_types/edit.html.erb %>
<%= render "form", project_type: @project_type, event_type: @event_type %>
```

```erb
<%# app/views/admin/event_types/_form.html.erb %>
<%= link_to admin_project_type_path(project_type), class: "d-inline-block mb-3" do %>
  <i class="bi bi-arrow-left"></i> Volver a <%= project_type.name %>
<% end %>

<%= panel_card("#{event_type.persisted? ? 'Editar' : 'Nuevo'} tipo de evento — #{project_type.name}") do %>
  <p class="text-muted">
    Los tipos de evento clasifican reuniones, hitos y entregas de este tipo
    de proyecto (por ejemplo, "Reunión de obra" o "Entrega final") y definen
    su color e ícono en el cronograma.
  </p>

  <%= form_with model: [:admin, project_type, event_type] do |form| %>
    <% if event_type.errors.any? %>
      <div class="alert alert-danger">
        <ul class="mb-0">
          <% event_type.errors.full_messages.each do |message| %>
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
    <div class="mb-3" data-controller="icon-picker">
      <%= form.label :icon, "Ícono", class: "form-label" %>
      <div class="input-group mb-2" style="max-width: 320px;">
        <span class="input-group-text"><i data-icon-picker-target="preview"></i></span>
        <%= form.text_field :icon, class: "form-control", data: { icon_picker_target: "input", action: "input->icon-picker#refresh" } %>
      </div>
      <div class="d-flex flex-wrap gap-1">
        <% %w[bi-calendar-event bi-flag bi-people bi-briefcase bi-clipboard-check
              bi-truck bi-tools bi-camera bi-exclamation-triangle bi-check-circle].each do |icon| %>
          <button type="button" class="btn btn-outline-secondary" data-icon-picker-target="option"
                  data-action="icon-picker#pick" data-icon-picker-icon-param="<%= icon %>">
            <i class="bi <%= icon %>"></i>
          </button>
        <% end %>
      </div>
      <div class="form-text">Elegí uno de la lista o escribí el nombre de cualquier ícono de <%= link_to "Bootstrap Icons", "https://icons.getbootstrap.com/", target: "_blank", rel: "noopener" %>.</div>
    </div>
    <%= form.submit class: "btn btn-primary" %>
  <% end %>
<% end %>
```

- [ ] **Step 6: Run test to verify it passes**

Run: `bin/rails test test/controllers/admin/event_types_controller_test.rb`
Expected: PASS (7 runs, 0 failures)

- [ ] **Step 7: Commit**

```bash
git add config/routes.rb app/controllers/admin/event_types_controller.rb app/views/admin/event_types app/models/event_type.rb test/controllers/admin/event_types_controller_test.rb
git commit -m "Agregar CRUD admin de tipos de evento"
```

---

### Task 4: "Tipos de evento" tab in the admin project type page

**Files:**
- Modify: `app/views/admin/project_types/show.html.erb`
- Test: `test/controllers/admin/project_types_controller_test.rb`

**Interfaces:**
- Consumes: `ProjectType#event_types` (Task 1), admin event_types routes (Task 3), existing `drag-reorder` Stimulus controller (`app/javascript/controllers/drag_reorder_controller.js`).

- [ ] **Step 1: Write the failing test**

Find the existing `show` test file `test/controllers/admin/project_types_controller_test.rb` and add:

```ruby
  test "show renders a Tipos de evento tab listing event types" do
    get admin_project_type_path(project_types(:instalaciones))
    assert_response :success
    assert_select "button", "Tipos de evento"
    assert_select "#tab-tipos-evento" do
      assert_select "li", text: /Reunión de obra/
      assert_select "li", text: /Entrega final/
    end
  end
```

(If that test file doesn't exist yet, create it with `require "test_helper"` and `class Admin::ProjectTypesControllerTest < ActionDispatch::IntegrationTest` + `setup { sign_in users(:juan) }`.)

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/admin/project_types_controller_test.rb -n "/Tipos de evento/"`
Expected: FAIL — no such button/element

- [ ] **Step 3: Add the tab**

Modify `app/views/admin/project_types/show.html.erb` — add a new `<li class="nav-item">` right after the "Subprocesos" tab button:

```erb
  <li class="nav-item" role="presentation">
    <button class="nav-link" data-bs-toggle="tab" data-bs-target="#tab-tipos-evento" type="button" role="tab">
      <i class="bi bi-calendar-event"></i> Tipos de evento
    </button>
  </li>
```

And add a new `<div class="tab-pane fade" id="tab-tipos-evento" role="tabpanel">` right after the `tab-subprocesos` pane closes, before `tab-duracion`:

```erb
  <div class="tab-pane fade" id="tab-tipos-evento" role="tabpanel">
    <div class="card mb-4">
      <div class="card-header">Tipos de evento</div>
      <div class="card-body">
        <p class="text-muted">
          Clasifican los eventos (reuniones, hitos, entregas) que se pueden
          cargar en un proyecto de este tipo, y definen su color e ícono en
          el cronograma. Arrastrá <span class="drag-handle">⠿</span> para
          reordenarlos.
        </p>
        <%= link_to new_admin_project_type_event_type_path(@project_type), class: "btn btn-primary btn-sm mb-2" do %>
          <i class="bi bi-plus-lg"></i> Nuevo tipo de evento
        <% end %>
        <% if @project_type.event_types.none? %>
          <p class="text-muted fst-italic">Todavía no hay tipos de evento definidos.</p>
        <% end %>
        <ol class="list-group list-group-numbered list-group-flush" id="event-types-list" data-controller="drag-reorder"
            data-drag-reorder-url-value="<%= reorder_admin_project_type_event_types_path(@project_type) %>"
            data-action="dragstart->drag-reorder#start dragend->drag-reorder#end dragover->drag-reorder#over drop->drag-reorder#drop">
          <% @project_type.event_types.each do |event_type| %>
            <li class="list-group-item d-flex justify-content-between align-items-center" data-id="<%= event_type.id %>">
              <span>
                <span class="drag-handle me-2" draggable="true" style="cursor: grab;">⠿</span>
                <i class="bi <%= event_type.icon %> me-1" style="color: <%= event_type.color %>;"></i>
                <%= event_type.name %>
              </span>
              <span>
                <%= link_to "Editar", edit_admin_project_type_event_type_path(@project_type, event_type), class: "btn btn-outline-secondary btn-sm" %>
                <%= button_to "Eliminar", admin_project_type_event_type_path(@project_type, event_type), method: :delete,
                      class: "btn btn-outline-danger btn-sm", form: { style: "display:inline-block", onsubmit: "return confirm('¿Eliminar tipo de evento?')" } %>
              </span>
            </li>
          <% end %>
        </ol>
      </div>
    </div>
  </div>
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/controllers/admin/project_types_controller_test.rb -n "/Tipos de evento/"`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/views/admin/project_types/show.html.erb test/controllers/admin/project_types_controller_test.rb
git commit -m "Agregar pestaña Tipos de evento en administración de tipos de proyecto"
```

---

### Task 5: `EventsController` (project-scoped create/update/destroy)

**Files:**
- Create: `app/controllers/events_controller.rb`
- Modify: `config/routes.rb`
- Test: `test/controllers/events_controller_test.rb`

**Interfaces:**
- Consumes: `Event`, `Project#events` (Task 2), `current_user.can_edit_project?(project)` (existing, used by `ProjectResponsiblesController`).
- Produces: routes `project_events_path(project)`, `project_event_path(project, event)`.

- [ ] **Step 1: Add routes**

Modify `config/routes.rb` — inside `resources :projects do ... end`, add next to `resources :project_responsibles`:

```ruby
    resources :events, only: [:create, :update, :destroy]
```

- [ ] **Step 2: Write the failing controller test**

```ruby
# test/controllers/events_controller_test.rb
require "test_helper"

class EventsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:juan) }
  setup do
    @project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    @event_type = event_types(:reunion_obra)
  end

  test "create adds a project-wide event" do
    assert_difference("@project.events.count", 1) do
      post project_events_path(@project), params: {
        event: { event_type_id: @event_type.id, title: "Kickoff", event_date: Date.current }
      }
    end
    assert_redirected_to project_path(@project)
    assert @project.events.last.project_wide?
  end

  test "create adds a stage-scoped event" do
    stage = @project.project_stages.first
    post project_events_path(@project), params: {
      event: { event_type_id: @event_type.id, title: "Kickoff", event_date: Date.current, project_stage_id: stage.id }
    }
    assert_equal stage, @project.events.last.project_stage
  end

  test "create with a blank title redirects with an error" do
    assert_no_difference("@project.events.count") do
      post project_events_path(@project), params: {
        event: { event_type_id: @event_type.id, title: "", event_date: Date.current }
      }
    end
    assert_redirected_to project_path(@project)
  end

  test "update changes an event's fields" do
    event = Event.create!(project: @project, event_type: @event_type, title: "Kickoff", event_date: Date.current)
    patch project_event_path(@project, event), params: { event: { title: "Kickoff reprogramado", status: "realizado" } }
    assert_redirected_to project_path(@project)
    event.reload
    assert_equal "Kickoff reprogramado", event.title
    assert_equal "realizado", event.status
  end

  test "destroy removes an event" do
    event = Event.create!(project: @project, event_type: @event_type, title: "Kickoff", event_date: Date.current)
    assert_difference("@project.events.count", -1) do
      delete project_event_path(@project, event)
    end
  end

  test "visor without edit access cannot create an event" do
    sign_in users(:maria)
    assert_no_difference("@project.events.count") do
      post project_events_path(@project), params: {
        event: { event_type_id: @event_type.id, title: "Kickoff", event_date: Date.current }
      }
    end
    assert_redirected_to root_path
  end
end
```

- [ ] **Step 3: Run test to verify it fails**

Run: `bin/rails test test/controllers/events_controller_test.rb`
Expected: FAIL — routing error / uninitialized constant `EventsController`

- [ ] **Step 4: Write the controller**

```ruby
# app/controllers/events_controller.rb
class EventsController < ApplicationController
  before_action :set_project
  before_action :authorize_edit!
  before_action :set_event, only: [:update, :destroy]

  def create
    @event = @project.events.new(event_params)
    if @event.save
      redirect_to project_path(@project)
    else
      redirect_to project_path(@project), alert: @event.errors.full_messages.to_sentence
    end
  end

  def update
    if @event.update(event_params)
      redirect_to project_path(@project)
    else
      redirect_to project_path(@project), alert: @event.errors.full_messages.to_sentence
    end
  end

  def destroy
    @event.destroy
    redirect_to project_path(@project)
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end

  def set_event
    @event = @project.events.find(params[:id])
  end

  def authorize_edit!
    return if current_user.can_edit_project?(@project)
    redirect_to root_path, alert: "No tenés permiso para hacer eso."
  end

  def event_params
    params.require(:event).permit(:event_type_id, :project_stage_id, :title, :event_date, :event_time, :responsible_id, :notes, :status)
  end
end
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bin/rails test test/controllers/events_controller_test.rb`
Expected: PASS (6 runs, 0 failures)

- [ ] **Step 6: Commit**

```bash
git add config/routes.rb app/controllers/events_controller.rb test/controllers/events_controller_test.rb
git commit -m "Agregar EventsController para crear, editar y eliminar eventos de un proyecto"
```

---

### Task 6: Event CRUD UI on the project show page (button, modals, table)

**Files:**
- Modify: `app/views/projects/show.html.erb`
- Create: `app/views/projects/_event_fields.html.erb`
- Create: `app/views/projects/_add_event_modal.html.erb`
- Create: `app/views/projects/_edit_event_modals.html.erb`
- Create: `app/views/projects/_events_table.html.erb`
- Modify: `test/controllers/projects_controller_test.rb`

**Interfaces:**
- Consumes: `EventsController` routes (Task 5), `Event`/`EventType` (Tasks 1-2), `ProjectType#event_types`, `ProjectType#responsibles` (existing), `Project#events`, `Project#project_stages`.

- [ ] **Step 1: Write the failing tests**

Add to `test/controllers/projects_controller_test.rb`:

```ruby
  test "show renders a + Evento button and an empty state when there are no events" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_path(project)
    assert_response :success
    assert_select "button", text: /Evento/
    assert_select "body", /Todavía no hay eventos cargados/
  end

  test "show lists existing events with type, title, stage and status" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    stage = project.project_stages.first
    Event.create!(project: project, event_type: event_types(:reunion_obra), title: "Kickoff", event_date: Date.current, project_stage: stage)

    get project_path(project)
    assert_response :success
    assert_select "body", /Kickoff/
    assert_select "body", /Reunión de obra/
    assert_select "body", Regexp.new(Regexp.escape(stage.name))
  end

  test "show hides the + Evento button and edit/delete actions from a visor without edit access" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    ProjectAccess.create!(project: project, user: users(:maria))
    Event.create!(project: project, event_type: event_types(:reunion_obra), title: "Kickoff", event_date: Date.current)

    sign_in users(:maria)
    get project_path(project)
    assert_response :success
    assert_select "button", { text: /Evento/, count: 0 }
    assert_select "a", { text: "Eliminar", count: 0 }
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n "/Evento/"`
Expected: FAIL — no such button/text on the page

- [ ] **Step 3: Write the shared fields partial**

```erb
<%# app/views/projects/_event_fields.html.erb %>
<% if form.object.errors.any? %>
  <div class="alert alert-danger">
    <ul class="mb-0">
      <% form.object.errors.full_messages.each do |message| %>
        <li><%= message %></li>
      <% end %>
    </ul>
  </div>
<% end %>
<div class="mb-3">
  <%= form.label :event_type_id, "Tipo", class: "form-label" %>
  <%= form.collection_select :event_type_id, project.project_type.event_types, :id, :name,
        { include_blank: "Elegí un tipo" }, class: "form-select" %>
</div>
<div class="mb-3">
  <%= form.label :title, "Título", class: "form-label" %>
  <%= form.text_field :title, class: "form-control" %>
</div>
<div class="row g-2 mb-3">
  <div class="col">
    <%= form.label :event_date, "Fecha", class: "form-label" %>
    <%= form.date_field :event_date, class: "form-control" %>
  </div>
  <div class="col">
    <%= form.label :event_time, "Hora", class: "form-label" %>
    <%= form.time_field :event_time, class: "form-control" %>
  </div>
</div>
<div class="mb-3">
  <%= form.label :project_stage_id, "Etapa", class: "form-label" %>
  <%= form.collection_select :project_stage_id, project.project_stages, :id, :name,
        { include_blank: "Todo el proyecto" }, class: "form-select" %>
</div>
<div class="mb-3">
  <%= form.label :responsible_id, "Responsable", class: "form-label" %>
  <%= form.collection_select :responsible_id, project.project_type.responsibles.order(:name), :id, :name,
        { include_blank: "Sin asignar" }, class: "form-select" %>
</div>
<div class="mb-3">
  <%= form.label :notes, "Notas", class: "form-label" %>
  <%= form.text_area :notes, class: "form-control", rows: 2 %>
</div>
<div class="mb-0">
  <%= form.label :status, "Estado", class: "form-label" %>
  <%= form.select :status, [["Pendiente", "pendiente"], ["Realizado", "realizado"]], {}, class: "form-select" %>
</div>
```

- [ ] **Step 4: Write the add/edit modal partials**

```erb
<%# app/views/projects/_add_event_modal.html.erb %>
<div class="modal fade" id="add-event-modal" tabindex="-1">
  <div class="modal-dialog">
    <div class="modal-content">
      <%= form_with model: Event.new, url: project_events_path(project) do |form| %>
        <div class="modal-header">
          <h5 class="modal-title">Agregar evento</h5>
          <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
        </div>
        <div class="modal-body">
          <%= render "event_fields", form: form, project: project %>
        </div>
        <div class="modal-footer">
          <button type="button" class="btn btn-outline-secondary" data-bs-dismiss="modal">Cancelar</button>
          <%= form.submit "Agregar", class: "btn btn-primary" %>
        </div>
      <% end %>
    </div>
  </div>
</div>
```

```erb
<%# app/views/projects/_edit_event_modals.html.erb %>
<% project.events.each do |event| %>
  <div class="modal fade" id="edit-event-modal-<%= event.id %>" tabindex="-1">
    <div class="modal-dialog">
      <div class="modal-content">
        <%= form_with model: event, url: project_event_path(project, event), method: :patch do |form| %>
          <div class="modal-header">
            <h5 class="modal-title">Editar evento</h5>
            <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
          </div>
          <div class="modal-body">
            <%= render "event_fields", form: form, project: project %>
          </div>
          <div class="modal-footer">
            <button type="button" class="btn btn-outline-secondary" data-bs-dismiss="modal">Cancelar</button>
            <%= form.submit "Guardar", class: "btn btn-primary" %>
          </div>
        <% end %>
      </div>
    </div>
  </div>
<% end %>
```

- [ ] **Step 5: Write the events table partial**

```erb
<%# app/views/projects/_events_table.html.erb %>
<div class="card mb-4">
  <div class="card-header d-flex justify-content-between align-items-center">
    Eventos
    <% if current_user.can_edit_project?(project) %>
      <button type="button" class="btn btn-primary btn-sm" data-bs-toggle="modal" data-bs-target="#add-event-modal">
        <i class="bi bi-plus-lg"></i> Evento
      </button>
    <% end %>
  </div>
  <div class="card-body p-0">
    <% events = project.events.includes(:event_type, :project_stage, :responsible).order(:event_date) %>
    <% if events.empty? %>
      <p class="text-muted p-3 mb-0">Todavía no hay eventos cargados.</p>
    <% else %>
      <table class="table table-striped mb-0">
        <thead>
          <tr><th>Fecha</th><th>Tipo</th><th>Título</th><th>Etapa</th><th>Responsable</th><th>Estado</th><th></th></tr>
        </thead>
        <tbody>
          <% events.each do |event| %>
            <tr>
              <td>
                <%= l(event.event_date, format: :long) %>
                <% if event.event_time.present? %> <%= event.event_time.strftime("%H:%M") %><% end %>
              </td>
              <td>
                <span class="badge me-1" style="background-color: <%= event.event_type.color %>">&nbsp;</span>
                <%= event.event_type.name %>
              </td>
              <td><%= event.title %></td>
              <td><%= event.project_stage&.name || "Todo el proyecto" %></td>
              <td><%= event.responsible&.name || "—" %></td>
              <td><%= event.status == "realizado" ? "Realizado" : "Pendiente" %></td>
              <td>
                <% if current_user.can_edit_project?(project) %>
                  <div class="d-flex gap-2">
                    <button type="button" class="btn btn-outline-secondary btn-sm" data-bs-toggle="modal" data-bs-target="#edit-event-modal-<%= event.id %>">
                      Editar
                    </button>
                    <%= button_to "Eliminar", project_event_path(project, event), method: :delete,
                          class: "btn btn-outline-danger btn-sm", form: { style: "display:inline-block", onsubmit: "return confirm('¿Eliminar evento?')" } %>
                  </div>
                <% end %>
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    <% end %>
  </div>
</div>
```

- [ ] **Step 6: Wire the partials into `show.html.erb`**

Modify `app/views/projects/show.html.erb` — insert right after the Gantt `</div>` that closes the "Cronograma" card (after the line `</div>` that follows `<% end %>` closing the `can_edit_project?` conditional at line ~79, i.e. right before the "Responsables" `<% if current_user.can_edit_project?(@project) %>` block):

```erb
<%= render "events_table", project: @project %>
<%= render "add_event_modal", project: @project if current_user.can_edit_project?(@project) %>
<%= render "edit_event_modals", project: @project if current_user.can_edit_project?(@project) %>
```

- [ ] **Step 7: Run test to verify it passes**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n "/Evento/"`
Expected: PASS (3 runs, 0 failures)

- [ ] **Step 8: Run the full projects controller test file to check for regressions**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: PASS, same failure count as before this task (0 new failures)

- [ ] **Step 9: Commit**

```bash
git add app/views/projects/show.html.erb app/views/projects/_event_fields.html.erb app/views/projects/_add_event_modal.html.erb app/views/projects/_edit_event_modals.html.erb app/views/projects/_events_table.html.erb test/controllers/projects_controller_test.rb
git commit -m "Agregar UI de eventos (crear, editar, listar) en el detalle de proyecto"
```

---

### Task 7: Render events on the Gantt — data wiring

**Files:**
- Modify: `app/views/projects/show.html.erb`
- Modify: `test/controllers/projects_controller_test.rb`

**Interfaces:**
- Consumes: `Project#events`, `EventType#color` (Tasks 1-2).
- Produces: three new `data-gantt-stage-editor-*` attributes read by Task 8's JS: `events-value` (stage-linked events), `event-colors-value` (color lookup for milestone tasks), and stage-less events folded into the existing `tasks` value as `type: "milestone"` entries.

- [ ] **Step 1: Write the failing test**

Add to `test/controllers/projects_controller_test.rb`:

```ruby
  test "show's Gantt data includes a milestone task for a project-wide event" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    event = Event.create!(project: project, event_type: event_types(:reunion_obra), title: "Kickoff", event_date: Date.current)

    get project_path(project)
    assert_response :success
    assert_select "[data-gantt-stage-editor-tasks-value]" do |elements|
      tasks = JSON.parse(elements.first["data-gantt-stage-editor-tasks-value"])
      milestone = tasks.find { |t| t["id"] == "event-#{event.id}" }
      assert milestone.present?
      assert_equal "milestone", milestone["type"]
      assert_equal "event-color-#{event.event_type_id}", milestone["custom_class"]
    end
  end

  test "show's Gantt data includes stage-linked events with a resolved color" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    stage = project.project_stages.first
    event = Event.create!(project: project, event_type: event_types(:reunion_obra), title: "Kickoff", event_date: Date.current, project_stage: stage)

    get project_path(project)
    assert_response :success
    assert_select "[data-gantt-stage-editor-events-value]" do |elements|
      events_data = JSON.parse(elements.first["data-gantt-stage-editor-events-value"])
      entry = events_data.find { |e| e["id"] == event.id }
      assert_equal stage.id.to_s, entry["project_stage_id"]
      assert_equal event_types(:reunion_obra).color, entry["color"]
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n "/Gantt data/"`
Expected: FAIL — no `data-gantt-stage-editor-events-value` attribute, no milestone task

- [ ] **Step 3: Compute and pass the data**

Modify `app/views/projects/show.html.erb` — in the existing `<% ... %>` block that builds `gantt_tasks` and `stage_colors` (around line 37-52), extend it to:

```erb
<%
  # ponytail: a stage with no dates gets a one-week placeholder window starting at
  # the project's creation date, so the chart always has something to draw. This is
  # a visual approximation, not real data — real dates come from editing the stage.
  # Project types with require_stage_dates skip that placeholder entirely instead:
  # an undated stage just doesn't appear on this Gantt until it has real dates.
  stages = @project.project_stages.includes(:stage_template).order(:id)
  require_dates = @project.project_type.require_stage_dates? || @project.project_type.auto_stage_duration_enabled?
  visible_stages = require_dates ? stages.reject(&:dates_missing?) : stages
  gantt_tasks = visible_stages.map do |stage|
    stage_start = stage.start_date || @project.created_at.to_date
    stage_end = stage.end_date || (stage_start + 7.days)
    {
      id: stage.id.to_s,
      name: stage.name,
      start: stage_start.to_s,
      end: stage_end.to_s,
      progress: stage.progress_percent,
      custom_class: "stage-color-#{stage.stage_template_id || 'none'}"
    }
  end
  stage_colors = stages.map { |stage| [stage.stage_template_id || "none", stage.stage_template&.name || "Sin subproceso", stage.stage_template&.color || "#6c757d"] }.uniq

  all_events = @project.events.includes(:event_type)
  stage_less_events = all_events.select(&:project_wide?)
  stage_linked_events = all_events.reject(&:project_wide?)

  stage_less_events.each do |event|
    gantt_tasks << {
      id: "event-#{event.id}",
      name: event.title,
      start: event.event_date.to_s,
      end: event.event_date.to_s,
      type: "milestone",
      custom_class: "event-color-#{event.event_type_id}"
    }
  end

  event_colors = all_events.map { |event| [event.event_type_id, event.event_type.name, event.event_type.color] }.uniq
  stage_events_data = stage_linked_events.map do |event|
    {
      id: event.id,
      project_stage_id: event.project_stage_id.to_s,
      event_date: event.event_date.to_s,
      title: event.title,
      color: event.event_type.color
    }
  end
%>
```

Then modify the `data-controller="gantt-stage-editor"` div to add the two new attributes:

```erb
  <div class="card-body" data-controller="gantt-stage-editor"
       data-gantt-stage-editor-patch-url-value="<%= project_path(@project) %>"
       data-gantt-stage-editor-tasks-value="<%= gantt_tasks.to_json %>"
       data-gantt-stage-editor-colors-value="<%= stage_colors.to_json %>"
       data-gantt-stage-editor-event-colors-value="<%= event_colors.to_json %>"
       data-gantt-stage-editor-events-value="<%= stage_events_data.to_json %>">
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n "/Gantt data/"`
Expected: PASS (2 runs, 0 failures)

- [ ] **Step 5: Commit**

```bash
git add app/views/projects/show.html.erb test/controllers/projects_controller_test.rb
git commit -m "Pasar datos de eventos al controlador Stimulus del Gantt"
```

---

### Task 8: Render event markers and milestones in the Gantt (JS)

**Files:**
- Modify: `app/javascript/controllers/gantt_stage_editor_controller.js`
- Create: `test/system/gantt_event_markers_test.rb`

**Interfaces:**
- Consumes: `eventsValue` and `eventColorsValue` Stimulus values (Task 7), `applyBarColors` from `app/javascript/gantt_bar_colors.js` (existing).
- Produces: a `.event-marker` SVG `<path>` per stage-linked event, positioned over its stage's bar and colored per `event_type.color`; native frappe-gantt `milestone` bars colored via `applyBarColors(..., "event-color")`; clicking either opens `#edit-event-modal-<id>` via `bootstrap.Modal.getOrCreateInstance(...).show()`.

- [ ] **Step 1: Write the failing system test**

```ruby
# test/system/gantt_event_markers_test.rb
require "application_system_test_case"

class GanttEventMarkersTest < ApplicationSystemTestCase
  test "the Gantt shows a colored marker over a stage for a stage-linked event" do
    project_type = project_types(:instalaciones)
    project = Project.create!(project_type: project_type, name: "Torre Norte", custom_fields: {})
    stage = project.project_stages.first
    stage.update!(start_date: Date.current, end_date: Date.current + 10.days)
    event_type = event_types(:reunion_obra)
    event_type.update!(color: "#ff00aa")
    event = Event.create!(
      project: project, event_type: event_type, title: "Kickoff",
      event_date: Date.current + 5.days, project_stage: stage
    )

    visit new_user_session_path
    fill_in "Correo electrónico", with: users(:juan).email
    fill_in "Contraseña", with: "password123"
    click_button "Iniciar sesión"
    assert_text users(:juan).email

    visit project_path(project)

    assert_selector ".event-marker", visible: :all
    fill_color = evaluate_script("document.querySelector('.event-marker').getAttribute('fill')")
    assert_equal "#ff00aa", fill_color

    assert_selector "#edit-event-modal-#{event.id}", visible: :all
  end

  test "the Gantt shows a native milestone bar for a project-wide event, colored by its type" do
    project_type = project_types(:instalaciones)
    project = Project.create!(project_type: project_type, name: "Torre Norte", custom_fields: {})
    event_type = event_types(:entrega_final)
    event_type.update!(color: "#00aaff")
    Event.create!(project: project, event_type: event_type, title: "Entrega", event_date: Date.current)

    visit new_user_session_path
    fill_in "Correo electrónico", with: users(:juan).email
    fill_in "Contraseña", with: "password123"
    click_button "Iniciar sesión"
    assert_text users(:juan).email

    visit project_path(project)

    bar_selector = ".bar-wrapper.event-color-#{event_type.id}"
    assert_selector bar_selector, visible: :all
    inline_style = evaluate_script("document.querySelector(#{bar_selector.to_json}).getAttribute('style')")
    assert_match "--bar-fill: #00aaff", inline_style
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/system/gantt_event_markers_test.rb`
Expected: FAIL — no `.event-marker` element found

- [ ] **Step 3: Update the Stimulus controller**

Replace the full contents of `app/javascript/controllers/gantt_stage_editor_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"
import { applyBarColors } from "gantt_bar_colors"

function toDateInputValue(date) {
  const year = date.getFullYear()
  const month = String(date.getMonth() + 1).padStart(2, "0")
  const day = String(date.getDate()).padStart(2, "0")
  return `${year}-${month}-${day}`
}

function isEventTaskId(id) {
  return String(id).startsWith("event-")
}

// Editable Gantt chart for a single project's stages - dragging a bar's dates
// or progress PATCHes the change back to the server. Also overlays a colored
// diamond marker on a stage's bar for each event tied to that stage (events
// with no stage are rendered as native frappe-gantt "milestone" tasks instead,
// already present in tasksValue - see projects/show.html.erb).
export default class extends Controller {
  static targets = ["chart", "viewModeButton"]
  static values = { patchUrl: String, tasks: Array, colors: Array, eventColors: Array, events: Array }

  connect() {
    if (this.tasksValue.length === 0) return

    this.gantt = new Gantt(this.chartTarget, this.tasksValue, {
      language: "es",
      popup: false,
      today_button: false,
      container_height: 630,
      view_mode_select: false,
      // frappe-gantt defaults infinite_padding to true, which wipes and
      // redraws every bar (this.clear() + this.render()) when the user
      // scrolls near an edge - that loses the --bar-fill custom property
      // applyColors() set on the old nodes. We don't need scroll-driven
      // date-range extension (tasksValue is already the full, fixed set).
      infinite_padding: false,
      on_click: (task) => {
        if (isEventTaskId(task.id)) return
        window.location.hash = `stage-${task.id}`
      },
      on_date_change: (task, start, end) => {
        if (isEventTaskId(task.id)) return
        this.saveStage(task.id, { start_date: toDateInputValue(start), end_date: toDateInputValue(end) })
      },
      on_progress_change: (task, progress) => {
        if (isEventTaskId(task.id)) return
        this.saveStage(task.id, { progress_percent: Math.round(progress) })
      }
    })
    this.refreshVisuals()
  }

  changeViewMode(event) {
    this.gantt.change_view_mode(event.currentTarget.dataset.mode)
    this.viewModeButtonTargets.forEach((btn) => btn.classList.remove("active"))
    event.currentTarget.classList.add("active")
    this.refreshVisuals()
  }

  refreshVisuals() {
    this.applyColors()
    this.drawEventMarkers()
  }

  applyColors() {
    applyBarColors(this.chartTarget, this.colorsValue, "stage-color")
    applyBarColors(this.chartTarget, this.eventColorsValue, "event-color")
  }

  // Overlays a small diamond on a stage's bar for each event scoped to that
  // stage. Position is derived from the stage bar's own rendered SVG geometry
  // (x/width/y/height already reflect the current view mode's column width),
  // not from frappe-gantt's internal date_utils/config - which keeps this
  // independent of the vendored library's private implementation details.
  drawEventMarkers() {
    this.chartTarget.querySelectorAll(".event-marker").forEach((el) => el.remove())
    const svg = this.chartTarget.querySelector("svg.gantt")
    if (!svg) return

    this.eventsValue.forEach((evt) => {
      const barWrapper = this.chartTarget.querySelector(`.bar-wrapper[data-id="${evt.project_stage_id}"]`)
      const stageTask = this.tasksValue.find((t) => String(t.id) === String(evt.project_stage_id))
      if (!barWrapper || !stageTask) return
      const bar = barWrapper.querySelector(".bar")
      if (!bar) return

      const barX = parseFloat(bar.getAttribute("x"))
      const barWidth = parseFloat(bar.getAttribute("width"))
      const barY = parseFloat(bar.getAttribute("y"))
      const barHeight = parseFloat(bar.getAttribute("height"))
      const stageStart = new Date(stageTask.start)
      const stageEnd = new Date(stageTask.end)
      const eventDate = new Date(evt.event_date)
      const span = stageEnd - stageStart
      const fraction = span > 0 ? Math.min(Math.max((eventDate - stageStart) / span, 0), 1) : 0

      const cx = barX + barWidth * fraction
      const cy = barY + barHeight / 2
      const size = 7

      const marker = document.createElementNS("http://www.w3.org/2000/svg", "path")
      marker.setAttribute("d", `M ${cx} ${cy - size} L ${cx + size} ${cy} L ${cx} ${cy + size} L ${cx - size} ${cy} Z`)
      marker.setAttribute("fill", evt.color)
      marker.setAttribute("stroke", "#fff")
      marker.setAttribute("stroke-width", "1.5")
      marker.setAttribute("class", "event-marker")
      marker.style.cursor = "pointer"

      const title = document.createElementNS("http://www.w3.org/2000/svg", "title")
      title.textContent = `${evt.title} — ${evt.event_date}`
      marker.appendChild(title)

      marker.addEventListener("click", (e) => {
        e.stopPropagation()
        const modalEl = document.getElementById(`edit-event-modal-${evt.id}`)
        if (modalEl) bootstrap.Modal.getOrCreateInstance(modalEl).show()
      })

      svg.appendChild(marker)
    })
  }

  saveStage(stageId, attrs) {
    fetch(this.patchUrlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
      },
      body: JSON.stringify({
        project: { project_stages_attributes: { "0": Object.assign({ id: stageId }, attrs) } }
      })
    })
      .then((response) => {
        if (!response.ok) throw new Error("save failed")
        return response.json()
      })
      .then((stages) => {
        const updated = stages.find((s) => String(s.id) === String(stageId))
        if (!updated) return
        const row = document.getElementById(`stage-${stageId}`)
        row.querySelector("input[name*='[start_date]']").value = updated.start_date || ""
        row.querySelector("input[name*='[end_date]']").value = updated.end_date || ""
        row.querySelector("input[name*='[progress_percent]']").value = updated.progress_percent
      })
      .catch(() => {
        this.gantt.refresh(this.tasksValue)
        this.refreshVisuals()
        alert("No se pudo guardar el cambio. Intenta de nuevo.")
      })
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/system/gantt_event_markers_test.rb`
Expected: PASS (2 runs, 0 failures)

- [ ] **Step 5: Run the existing Gantt color persistence system test to check for regressions**

Run: `bin/rails test test/system/gantt_color_persistence_test.rb`
Expected: PASS (unchanged)

- [ ] **Step 6: Run the full test suite**

Run: `bin/rails test`
Expected: PASS, 0 failures, 0 errors

- [ ] **Step 7: Commit**

```bash
git add app/javascript/controllers/gantt_stage_editor_controller.js test/system/gantt_event_markers_test.rb
git commit -m "Renderizar eventos como marcadores y milestones en el Gantt del proyecto"
```

---

## Self-Review Notes

- **Spec coverage:** `event_types` model+admin (Tasks 1, 3, 4); `events` model (Task 2); event CRUD UI with the same `can_edit_project?` gate as stage editing (Tasks 5, 6); Gantt overlay for stage-linked events + milestone row for stage-less events, both colored by `event_type.color` (Tasks 7, 8); events listing table (Task 6). Out-of-scope items (`_project_type_section.html.erb`, notifications, recurrence) are untouched by this plan.
- **Refinement from spec:** the spec described a popover-with-edit-link on marker click; this plan opens the existing edit modal directly instead (Task 8) — same outcome (click a marker, see and change all its details) with no extra popover-building code, consistent with reusing `bootstrap.Modal` the way `help_controller.js` already does.
- **Type/name consistency checked:** `EventType#events`, `Event#event_type`/`#project_stage`/`#responsible`/`#project_wide?`, Stimulus values `eventsValue`/`eventColorsValue`, and the `event-color-<id>` / `.event-marker` class names are used identically across Tasks 1-2 (models), 7 (view data), and 8 (JS).
- **No placeholders:** every step has real, runnable code or an exact test command.
