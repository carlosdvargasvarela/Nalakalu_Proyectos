# Auth (Devise), navbar y Gantt real — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Gate the app behind Devise login, add a Bootstrap navbar, replace `ProjectStage`'s loose `assigned_user_id` integer with a real `User` reference, add a stage-editing form, and replace the static HTML stage table with a real Frappe Gantt chart.

**Architecture:** Devise (`database_authenticatable, registerable, rememberable, validatable` — no roles, no email-based recovery) gates `ApplicationController`. A navbar partial renders session state in the layout. `ProjectStage` gets a `user_id` FK. A new `ProjectStagesController` (nested under `projects`) lets a signed-in user edit a stage's dates/progress/responsible. `projects#show` renders stages via Frappe Gantt, loaded from a CDN `<script>` tag (same pattern already used for Bootstrap) — no importmap changes.

**Tech Stack:** Rails 7.2.3, Devise (gem, version unpinned — Bundler resolves latest compatible with Rails 7.2), Frappe Gantt 0.6.1 (CDN), Minitest, existing Postgres/Docker setup.

## Global Constraints

- Devise: **no roles** — any authenticated user can reach every page, including `/admin/*`. Modules: `database_authenticatable, registerable, rememberable, validatable`. **No** `:recoverable` (no mailer configured) and **no** `:confirmable`/`:lockable`.
- Registration is open (Devise's default `:registerable` behavior, no invite/approval flow).
- `ApplicationController` must skip its own auth filter for Devise's controllers (`unless: :devise_controller?`) — otherwise the sign-in page itself redirects to the sign-in page.
- `ProjectStage#user_id` is `optional: true` — a stage without a responsible user must remain valid.
- Frappe Gantt is loaded via CDN `<script>`/`<link>` tags in the view, pinned to version `0.6.1`. No new build tooling, no importmap changes.
- A `ProjectStage` with no `start_date`/`end_date` renders in the Gantt with a one-week placeholder window starting at its project's `created_at` date — mark this fallback with a `ponytail:` comment, it is a visual approximation, not real data.
- Every task must leave the full `bin/rails test` suite green. Gating the app behind auth breaks every existing controller test that doesn't sign in — Task 1 is responsible for fixing all of them, not just adding the feature.

---

## File Structure

| File | Responsibility |
|---|---|
| `Gemfile` | adds `devise` |
| `app/models/user.rb` | Devise User model (generated, then trimmed to our module list) |
| `app/controllers/application_controller.rb` | global `authenticate_user!` gate |
| `test/fixtures/users.yml` | one fixture user for signed-in tests |
| `test/test_helper.rb` | wires `Devise::Test::IntegrationHelpers` into integration tests |
| `test/controllers/authentication_test.rb` | anonymous-redirected / signed-in-allowed |
| `app/views/layouts/_navbar.html.erb` | navbar partial |
| `app/views/layouts/application.html.erb` | renders navbar + flash |
| `test/controllers/navbar_test.rb` | navbar renders session-aware links |
| `db/migrate/..._add_user_to_project_stages.rb` | `user_id` FK, drops `assigned_user_id` |
| `app/models/project_stage.rb` | `belongs_to :user, optional: true` |
| `app/controllers/project_stages_controller.rb` | `edit`/`update` for a stage |
| `app/views/project_stages/edit.html.erb` | stage edit form |
| `test/controllers/project_stages_controller_test.rb` | stage update behavior |
| `app/views/projects/show.html.erb` | Gantt div + show_in_gantt summary table (replaces old stage table) |

---

## Task 1: Devise auth, gate the app, fix the existing suite

**Files:**
- Modify: `Gemfile`
- Create (generated): `app/models/user.rb`, `db/migrate/<ts>_devise_create_users.rb`, `config/initializers/devise.rb`, `config/locales/devise.en.yml`
- Modify: `config/routes.rb` (generator adds `devise_for :users`)
- Modify: `app/controllers/application_controller.rb`
- Create: `test/fixtures/users.yml`
- Modify: `test/test_helper.rb`
- Create: `test/controllers/authentication_test.rb`
- Modify: `test/controllers/projects_controller_test.rb`, `test/controllers/admin/project_types_controller_test.rb`, `test/controllers/admin/field_definitions_controller_test.rb`, `test/controllers/admin/stage_templates_controller_test.rb`

**Interfaces:**
- Consumes: nothing (foundation task).
- Produces: `User` model, `current_user`/`user_signed_in?`/`devise_controller?` helpers (from Devise, available in every controller/view from this task on), `users(:juan)` fixture, `sign_in` test helper — all later tasks and tests use `sign_in users(:juan)` in their `setup` block.

- [ ] **Step 1: Add the gem and install**

Edit `Gemfile`, add near the other gems (before the `minitest` pin at the bottom):

```ruby
gem "devise"
```

```bash
bundle install
```

- [ ] **Step 2: Run the Devise installer**

```bash
bin/rails generate devise:install
```

This creates `config/initializers/devise.rb` and `config/locales/devise.en.yml`. No manual edits needed — we don't send mail (no `:recoverable`), so the mailer `default_url_options` warning it prints can be ignored.

- [ ] **Step 3: Generate the User model**

```bash
bin/rails generate devise User
```

This creates a migration (e.g. `db/migrate/20260723XXXXXX_devise_create_users.rb`), `app/models/user.rb`, and adds `devise_for :users` to the top of `config/routes.rb`. The generated model looks like:

```ruby
class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable
end
```

- [ ] **Step 4: Trim to our module list**

Edit `app/models/user.rb` — remove `:recoverable` (no mailer configured, out of scope per the design spec):

```ruby
class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :rememberable, :validatable
end
```

Leave the generated migration as-is (it still creates `reset_password_token`/`reset_password_sent_at` columns — unused since we don't declare `:recoverable`, but harmless, and hand-editing a generated migration risks breaking the index it defines).

- [ ] **Step 5: Migrate**

```bash
bin/rails db:migrate
```

Expected: creates a `users` table with `email`, `encrypted_password`, `reset_password_token`, `reset_password_sent_at`, `remember_created_at`, timestamps, and a unique index on `email`.

- [ ] **Step 6: Add the test fixture**

Create `test/fixtures/users.yml`:

```yaml
juan:
  email: juan@example.com
  encrypted_password: <%= Devise::Encryptor.digest(User, "password123") %>
```

- [ ] **Step 7: Wire sign_in into integration tests**

Edit `test/test_helper.rb` — add this block after the `require "rails/test_help"` line, outside the existing `ActiveSupport::TestCase` block:

```ruby
class ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
end
```

- [ ] **Step 8: Write the failing auth test**

Create `test/controllers/authentication_test.rb`:

```ruby
require "test_helper"

class AuthenticationTest < ActionDispatch::IntegrationTest
  test "anonymous visitor is redirected to sign in" do
    get root_path
    assert_redirected_to new_user_session_path
  end

  test "signed in user can reach the projects index" do
    sign_in users(:juan)
    get root_path
    assert_response :success
  end
end
```

- [ ] **Step 9: Run it to verify it fails**

```bash
bin/rails test test/controllers/authentication_test.rb
```

Expected: FAIL on the first test — `get root_path` currently returns `200 OK` for anyone, so `assert_redirected_to` fails. The second test currently passes already (nothing to gate yet), which is fine at this stage.

- [ ] **Step 10: Gate the app**

Edit `app/controllers/application_controller.rb`:

```ruby
class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  before_action :authenticate_user!, unless: :devise_controller?
end
```

- [ ] **Step 11: Run the auth test to verify it passes**

```bash
bin/rails test test/controllers/authentication_test.rb
```

Expected: PASS (2 runs, 0 failures).

- [ ] **Step 12: Run the full suite — expect the pre-existing tests to now fail**

```bash
bin/rails test
```

Expected: FAIL — every test in `projects_controller_test.rb` and `test/controllers/admin/*_test.rb` now gets redirected to sign-in instead of the response it expects. This is the expected, controlled breakage this task exists to fix.

- [ ] **Step 13: Sign in inside each pre-existing controller test**

Edit `test/controllers/projects_controller_test.rb` — add a `setup` block right after the class line:

```ruby
class ProjectsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:juan) }

  test "index lists projects" do
```

(Keep every existing test unchanged below this — only the new `setup` line and the now-consistent indentation of what follows matter.)

Edit `test/controllers/admin/project_types_controller_test.rb` similarly:

```ruby
class Admin::ProjectTypesControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:juan) }

  test "index lists project types" do
```

Edit `test/controllers/admin/field_definitions_controller_test.rb` — this file already has a `setup` block, add sign-in as a second one right above it:

```ruby
class Admin::FieldDefinitionsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:juan) }
  setup { @project_type = project_types(:instalaciones) }
```

Edit `test/controllers/admin/stage_templates_controller_test.rb` the same way:

```ruby
class Admin::StageTemplatesControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:juan) }
  setup { @project_type = project_types(:instalaciones) }
```

- [ ] **Step 14: Run the full suite to verify it's green again**

```bash
bin/rails test
```

Expected: all tests pass (37 pre-existing + 2 new `authentication_test.rb` = 39 runs, 0 failures).

- [ ] **Step 15: Commit**

```bash
git add Gemfile Gemfile.lock app/models/user.rb app/controllers/application_controller.rb \
  config/initializers/devise.rb config/locales/devise.en.yml config/routes.rb db/migrate db/schema.rb \
  test/fixtures/users.yml test/test_helper.rb test/controllers/authentication_test.rb \
  test/controllers/projects_controller_test.rb test/controllers/admin
git commit -m "Add Devise auth, gate the app behind login"
```

---

## Task 2: Navbar

**Files:**
- Create: `app/views/layouts/_navbar.html.erb`
- Modify: `app/views/layouts/application.html.erb`
- Test: `test/controllers/navbar_test.rb`

**Interfaces:**
- Consumes: `user_signed_in?`, `current_user`, `new_user_session_path`, `new_user_registration_path`, `destroy_user_session_path` (Devise, Task 1), `projects_path`, `admin_project_types_path` (existing routes).
- Produces: nothing consumed by later tasks — this is a leaf, purely additive to the layout.

- [ ] **Step 1: Write the failing test**

Create `test/controllers/navbar_test.rb`:

```ruby
require "test_helper"

class NavbarTest < ActionDispatch::IntegrationTest
  test "navbar shows session-aware links when signed in" do
    sign_in users(:juan)
    get root_path
    assert_response :success
    assert_select "nav a[href=?]", projects_path
    assert_select "nav a[href=?]", admin_project_types_path
    assert_select "nav", /juan@example\.com/
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

```bash
bin/rails test test/controllers/navbar_test.rb
```

Expected: FAIL — `nav` doesn't exist in the current layout, so all three `assert_select` calls fail.

- [ ] **Step 3: Write the navbar partial**

Create `app/views/layouts/_navbar.html.erb`:

```erb
<nav class="navbar navbar-expand-lg navbar-light bg-light mb-4">
  <div class="container-fluid">
    <%= link_to "Nalakalu Proyectos", root_path, class: "navbar-brand" %>
    <div class="navbar-nav me-auto">
      <%= link_to "Proyectos", projects_path, class: "nav-link" %>
      <%= link_to "Administración", admin_project_types_path, class: "nav-link" %>
    </div>
    <div class="navbar-nav">
      <% if user_signed_in? %>
        <span class="navbar-text me-3"><%= current_user.email %></span>
        <%= button_to "Cerrar sesión", destroy_user_session_path, method: :delete, class: "btn btn-outline-secondary btn-sm" %>
      <% else %>
        <%= link_to "Iniciar sesión", new_user_session_path, class: "btn btn-outline-primary btn-sm me-2" %>
        <%= link_to "Registrarse", new_user_registration_path, class: "btn btn-primary btn-sm" %>
      <% end %>
    </div>
  </div>
</nav>
```

- [ ] **Step 4: Render it from the layout, with flash messages**

Edit `app/views/layouts/application.html.erb`:

```erb
  <body>
    <%= render "layouts/navbar" %>
    <div class="container py-4">
      <% if notice %>
        <div class="alert alert-success"><%= notice %></div>
      <% end %>
      <% if alert %>
        <div class="alert alert-danger"><%= alert %></div>
      <% end %>
      <%= yield %>
    </div>
  </body>
```

- [ ] **Step 5: Run test to verify it passes**

```bash
bin/rails test test/controllers/navbar_test.rb
```

Expected: PASS (1 run, 0 failures).

- [ ] **Step 6: Run the full suite to confirm no regressions**

```bash
bin/rails test
```

Expected: all green (40 runs).

- [ ] **Step 7: Commit**

```bash
git add app/views/layouts test/controllers/navbar_test.rb
git commit -m "Add navbar with session-aware links"
```

---

## Task 3: ProjectStage#user_id (replaces assigned_user_id)

**Files:**
- Create: `db/migrate/<ts>_add_user_to_project_stages.rb`
- Modify: `app/models/project_stage.rb`
- Modify: `app/views/projects/show.html.erb`
- Test: `test/models/project_stage_test.rb`

**Interfaces:**
- Consumes: `User` (Task 1).
- Produces: `ProjectStage#user` (`belongs_to`, optional), `ProjectStage#user_id` column — consumed by Task 4's form and Task 5's Gantt task serialization.

- [ ] **Step 1: Generate and edit the migration**

```bash
bin/rails generate migration AddUserToProjectStages
```

Edit the generated file (`db/migrate/<ts>_add_user_to_project_stages.rb`):

```ruby
class AddUserToProjectStages < ActiveRecord::Migration[7.2]
  def change
    add_reference :project_stages, :user, null: true, foreign_key: true
    remove_column :project_stages, :assigned_user_id, :integer
  end
end
```

- [ ] **Step 2: Write the failing test**

Edit `test/models/project_stage_test.rb`, add at the end of the class (before the final `end`):

```ruby
  test "valid with and without an assigned user" do
    project = Project.create!(
      project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {}
    )
    stage = project.project_stages.first

    stage.user = users(:juan)
    assert stage.valid?, stage.errors.full_messages.to_s

    stage.user = nil
    assert stage.valid?, stage.errors.full_messages.to_s
  end
```

- [ ] **Step 3: Run migration and test to verify it fails**

```bash
bin/rails db:migrate
bin/rails test test/models/project_stage_test.rb
```

Expected: FAIL — `undefined method 'user=' for an instance of ProjectStage` (no association yet).

- [ ] **Step 4: Add the association**

Edit `app/models/project_stage.rb`:

```ruby
class ProjectStage < ApplicationRecord
  belongs_to :project
  belongs_to :stage_template, optional: true
  belongs_to :user, optional: true

  validates :name, presence: true
end
```

- [ ] **Step 5: Fix the view reference to the removed column**

Edit `app/views/projects/show.html.erb` — replace the `Responsable` cell (`<td><%= stage.assigned_user_id %></td>`) with:

```erb
        <td><%= stage.user&.email %></td>
```

- [ ] **Step 6: Run test to verify it passes**

```bash
bin/rails test test/models/project_stage_test.rb
```

Expected: PASS (4 runs — 3 existing + 1 new — 0 failures).

- [ ] **Step 7: Run the full suite to confirm no regressions**

```bash
bin/rails test
```

Expected: all green (41 runs).

- [ ] **Step 8: Commit**

```bash
git add db/migrate db/schema.rb app/models/project_stage.rb app/views/projects/show.html.erb test/models/project_stage_test.rb
git commit -m "Replace ProjectStage#assigned_user_id with a real User reference"
```

---

## Task 4: Stage editing form

**Files:**
- Modify: `config/routes.rb`
- Create: `app/controllers/project_stages_controller.rb`
- Create: `app/views/project_stages/edit.html.erb`
- Modify: `app/models/project_stage.rb`
- Test: `test/controllers/project_stages_controller_test.rb`

**Interfaces:**
- Consumes: `ProjectStage#user` (Task 3), `Project` (Tasks 2-7 of the original plan).
- Produces: `edit_project_project_stage_path`, `project_project_stage_path` route helpers — consumed by Task 5's Gantt bar click-through.

- [ ] **Step 1: Add the nested route**

Edit `config/routes.rb`:

```ruby
  resources :projects do
    resources :project_stages, only: [:edit, :update]
  end
```

(Replaces the existing bare `resources :projects` line.)

- [ ] **Step 2: Write the failing test**

Create `test/controllers/project_stages_controller_test.rb`:

```ruby
require "test_helper"

class ProjectStagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:juan)
    @project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    @stage = @project.project_stages.first
  end

  test "update saves start_date, end_date, progress_percent and user" do
    patch project_project_stage_path(@project, @stage), params: {
      project_stage: {
        start_date: "2026-08-01", end_date: "2026-08-10",
        progress_percent: 50, user_id: users(:juan).id
      }
    }
    assert_redirected_to project_path(@project)

    @stage.reload
    assert_equal Date.parse("2026-08-01"), @stage.start_date
    assert_equal Date.parse("2026-08-10"), @stage.end_date
    assert_equal 50, @stage.progress_percent
    assert_equal users(:juan), @stage.user
  end

  test "update with progress_percent out of range re-renders form with error" do
    patch project_project_stage_path(@project, @stage), params: {
      project_stage: { progress_percent: 150 }
    }
    assert_response :unprocessable_entity
  end

  test "editing a stage from another project 404s" do
    other_project = Project.create!(project_type: project_types(:instalaciones), name: "Otro", custom_fields: {})
    other_stage = other_project.project_stages.first

    assert_raises(ActiveRecord::RecordNotFound) do
      get edit_project_project_stage_path(@project, other_stage)
    end
  end
end
```

- [ ] **Step 3: Run test to verify it fails**

```bash
bin/rails test test/controllers/project_stages_controller_test.rb
```

Expected: FAIL — `uninitialized constant ProjectStagesController`.

- [ ] **Step 4: Add the progress_percent bound validation**

Edit `app/models/project_stage.rb`:

```ruby
class ProjectStage < ApplicationRecord
  belongs_to :project
  belongs_to :stage_template, optional: true
  belongs_to :user, optional: true

  validates :name, presence: true
  validates :progress_percent, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
end
```

- [ ] **Step 5: Write the controller**

Create `app/controllers/project_stages_controller.rb`:

```ruby
class ProjectStagesController < ApplicationController
  before_action :set_project
  before_action :set_project_stage

  def edit
  end

  def update
    if @project_stage.update(project_stage_params)
      redirect_to project_path(@project)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end

  def set_project_stage
    @project_stage = @project.project_stages.find(params[:id])
  end

  def project_stage_params
    params.require(:project_stage).permit(:start_date, :end_date, :progress_percent, :user_id)
  end
end
```

- [ ] **Step 6: Write the view**

Create `app/views/project_stages/edit.html.erb`:

```erb
<h1>Editar etapa — <%= @project_stage.name %></h1>

<%= form_with model: [@project, @project_stage] do |form| %>
  <% if @project_stage.errors.any? %>
    <div class="alert alert-danger">
      <ul class="mb-0">
        <% @project_stage.errors.full_messages.each do |message| %>
          <li><%= message %></li>
        <% end %>
      </ul>
    </div>
  <% end %>

  <div class="mb-3">
    <%= form.label :start_date, class: "form-label" %>
    <%= form.date_field :start_date, class: "form-control" %>
  </div>
  <div class="mb-3">
    <%= form.label :end_date, class: "form-label" %>
    <%= form.date_field :end_date, class: "form-control" %>
  </div>
  <div class="mb-3">
    <%= form.label :progress_percent, "% Avance", class: "form-label" %>
    <%= form.number_field :progress_percent, min: 0, max: 100, class: "form-control" %>
  </div>
  <div class="mb-3">
    <%= form.label :user_id, "Responsable", class: "form-label" %>
    <%= form.select :user_id, User.all.collect { |u| [u.email, u.id] }, { include_blank: true }, class: "form-select" %>
  </div>

  <%= form.submit "Guardar", class: "btn btn-primary" %>
<% end %>

<%= link_to "Volver", project_path(@project), class: "btn btn-link" %>
```

- [ ] **Step 7: Run test to verify it passes**

```bash
bin/rails test test/controllers/project_stages_controller_test.rb
```

Expected: PASS (3 runs, 0 failures).

- [ ] **Step 8: Run the full suite to confirm no regressions**

```bash
bin/rails test
```

Expected: all green (44 runs).

- [ ] **Step 9: Commit**

```bash
git add config/routes.rb app/controllers/project_stages_controller.rb app/views/project_stages \
  app/models/project_stage.rb test/controllers/project_stages_controller_test.rb
git commit -m "Add stage editing: dates, progress and responsible user"
```

---

## Task 5: Real Gantt chart (Frappe Gantt)

**Files:**
- Modify: `app/views/projects/show.html.erb`
- Modify: `test/controllers/projects_controller_test.rb`

**Interfaces:**
- Consumes: `ProjectStage#start_date/#end_date/#progress_percent/#name` (existing), `edit_project_project_stage_path` (Task 4), `Project#created_at` (existing).
- Produces: nothing — this is the final, leaf-level view task.

- [ ] **Step 1: Update the existing test for the new stage summary table**

The "show renders a Gantt column..." test from the original plan's Task 9 asserted the show_in_gantt value repeated once per stage row. That table now shows project-level fields exactly once (a single summary row next to the chart, not one row per stage). Edit `test/controllers/projects_controller_test.rb` — replace that test:

```ruby
  test "show renders a Gantt column for each show_in_gantt field, with the project's value shown once" do
    project = Project.create!(
      project_type: project_types(:instalaciones), name: "Torre Norte",
      custom_fields: { cliente: "Acme S.A." }
    )
    get project_path(project)
    assert_response :success
    assert_select "table th", text: "Cliente"
    assert_select "table td", text: "Acme S.A.", count: 1
  end
```

Add a new test right after it, in the same file:

```ruby
  test "show renders the Gantt chart container with one task per stage" do
    project = Project.create!(
      project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {}
    )
    get project_path(project)
    assert_response :success
    assert_select "#gantt"
    assert_select "script#gantt-tasks", text: /#{project.project_stages.first.name}/
  end
```

- [ ] **Step 2: Run to verify it fails**

```bash
bin/rails test test/controllers/projects_controller_test.rb
```

Expected: FAIL — the summary-table test fails because the current view still repeats the value per stage row (count mismatch); the new Gantt test fails because `#gantt` and `script#gantt-tasks` don't exist yet.

- [ ] **Step 3: Rewrite the subprocess section of the show view**

Edit `app/views/projects/show.html.erb` — replace everything from `<% gantt_fields = ... %>` to the end of the file with:

```erb
<% content_for :head do %>
  <link href="https://cdn.jsdelivr.net/npm/frappe-gantt@0.6.1/dist/frappe-gantt.css" rel="stylesheet">
<% end %>

<% gantt_fields = @project.project_type.field_definitions.where(show_in_gantt: true).order(:position) %>
<h2>Gantt</h2>

<% if gantt_fields.any? %>
  <table class="table table-sm table-bordered w-auto mb-3">
    <thead>
      <tr><% gantt_fields.each do |field| %><th><%= field.label %></th><% end %></tr>
    </thead>
    <tbody>
      <tr><% gantt_fields.each do |field| %><td><%= @project.custom_fields[field.key] %></td><% end %></tr>
    </tbody>
  </table>
<% end %>

<div id="gantt" class="mb-4"></div>

<%
  # ponytail: a stage with no dates gets a one-week placeholder window starting at
  # the project's creation date, so the chart always has something to draw. This is
  # a visual approximation, not real data — real dates come from editing the stage.
  gantt_tasks = @project.project_stages.order(:id).map do |stage|
    stage_start = stage.start_date || @project.created_at.to_date
    stage_end = stage.end_date || (stage_start + 7.days)
    {
      id: stage.id.to_s,
      name: stage.name,
      start: stage_start.to_s,
      end: stage_end.to_s,
      progress: stage.progress_percent,
      edit_url: edit_project_project_stage_path(@project, stage)
    }
  end
%>
<script type="application/json" id="gantt-tasks"><%== gantt_tasks.to_json %></script>

<script src="https://cdn.jsdelivr.net/npm/frappe-gantt@0.6.1/dist/frappe-gantt.min.js"></script>
<script>
  document.addEventListener("DOMContentLoaded", function () {
    var tasks = JSON.parse(document.getElementById("gantt-tasks").textContent);
    if (tasks.length > 0) {
      new Gantt("#gantt", tasks, {
        on_click: function (task) { window.location = task.edit_url; }
      });
    }
  });
</script>
```

- [ ] **Step 4: Run test to verify it passes**

```bash
bin/rails test test/controllers/projects_controller_test.rb
```

Expected: PASS (7 runs, 0 failures) — the file had 6 tests; one was replaced 1-for-1 and one new test was added.

- [ ] **Step 5: Run the full suite to confirm no regressions**

```bash
bin/rails test
```

Expected: all green (45 runs — 44 from Task 4 plus the one new Gantt-container test added in Step 1).

- [ ] **Step 6: Manual browser verification**

```bash
bin/rails server -p 3000 -d
```

Open `http://localhost:3000`, sign in (or register), open a project with stages, confirm the Gantt chart renders bars (even with placeholder dates), and clicking a bar navigates to that stage's edit form. Stop the server:

```bash
kill $(cat tmp/pids/server.pid)
```

- [ ] **Step 7: Commit**

```bash
git add app/views/projects/show.html.erb test/controllers/projects_controller_test.rb
git commit -m "Replace static stage table with a real Frappe Gantt chart"
```

---
