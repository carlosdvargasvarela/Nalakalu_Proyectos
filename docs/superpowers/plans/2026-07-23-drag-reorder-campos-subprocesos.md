# Reordenar Campos y Subprocesos por arrastre — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let an admin drag-reorder `FieldDefinition`s and `StageTemplate`s within a project type, using native HTML5 drag-and-drop (no new JS library) with a per-row drag handle and instant AJAX persistence.

**Architecture:** Task 1 adds a `reorder` collection action to both `Admin::FieldDefinitionsController` and `Admin::StageTemplatesController` (each scoped to its own `project_type`, updating `position` per the submitted id order). Task 2 adds the drag-handle markup and the vanilla-JS drag/drop script to `admin/project_types/show.html.erb`, which calls those endpoints.

**Tech Stack:** Ruby on Rails, Minitest, native HTML5 Drag and Drop API (no jQuery/Sortable.js/other JS library).

## Global Constraints

- No new gems, no new JS library — native browser Drag and Drop API only.
- `reorder` uses `update_all` (not `update`) since it's only ever touching the `position` column — no need to trigger model validations/callbacks for a pure reorder.
- Each `reorder` action scopes its update through `@project_type.field_definitions`/`@project_type.stage_templates` (`.where(id: id)`) so an id belonging to a different `project_type` can never be repositioned by this endpoint.
- Only the drag-handle element (`.drag-handle`) has `draggable="true"` — never the whole `<li>` — so clicking "Editar"/"Eliminar" in the same row never accidentally starts a drag.

---

### Task 1: `reorder` endpoints

**Files:**
- Modify: `config/routes.rb`
- Modify: `app/controllers/admin/field_definitions_controller.rb`
- Modify: `app/controllers/admin/stage_templates_controller.rb`
- Modify: `test/controllers/admin/field_definitions_controller_test.rb`
- Modify: `test/controllers/admin/stage_templates_controller_test.rb`

**Interfaces:**
- Consumes: `FieldDefinition#position`/`StageTemplate#position` (unchanged columns).
- Produces: `reorder_admin_project_type_field_definitions_path(project_type)`, `reorder_admin_project_type_stage_templates_path(project_type)` — consumed by Task 2's view/JS.

- [ ] **Step 1: Add the routes**

Edit `config/routes.rb`:

```ruby
Rails.application.routes.draw do
  devise_for :users
  get "up" => "rails/health#show", as: :rails_health_check
  get "manifest.json" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker.js" => "rails/pwa#service_worker", as: :pwa_service_worker

  namespace :admin do
    resources :project_types do
      resources :field_definitions, except: [:index, :show] do
        patch :reorder, on: :collection
      end
      resources :stage_templates, except: [:index, :show] do
        patch :reorder, on: :collection
      end
    end
    resources :installers
  end

  get "projects/seguimiento", to: "projects#tracker", as: :tracker_projects
  resources :projects

  resources :imports, only: [:new, :create]
  get "imports/template", to: "imports#template", as: :template_imports

  root "projects#index"
end
```

- [ ] **Step 2: Write the failing tests**

Add to `test/controllers/admin/field_definitions_controller_test.rb`, inside the existing test class:

```ruby
  test "reorder updates position according to the submitted id order" do
    cliente = field_definitions(:cliente)
    instalador = field_definitions(:instalador)

    patch reorder_admin_project_type_field_definitions_path(@project_type), params: { ids: [instalador.id, cliente.id] }, as: :json
    assert_response :success

    assert_equal 0, instalador.reload.position
    assert_equal 1, cliente.reload.position
    assert_equal [instalador, cliente], @project_type.field_definitions.order(:position).to_a
  end

  test "reorder ignores an id that doesn't belong to this project_type" do
    other_type = ProjectType.create!(name: "Mantenimiento", slug: "mantenimiento")
    other_field = other_type.field_definitions.create!(key: "x", label: "X", data_type: "text", position: 0)
    cliente = field_definitions(:cliente)

    patch reorder_admin_project_type_field_definitions_path(@project_type), params: { ids: [other_field.id, cliente.id] }, as: :json
    assert_response :success

    assert_equal 0, other_field.reload.position
    assert_equal 0, cliente.reload.position
  end
```

(`test/controllers/admin/field_definitions_controller_test.rb` already has `setup { sign_in users(:juan) }` and `setup { @project_type = project_types(:instalaciones) }` at the top of the class — just add the two new tests, no setup changes needed.)

Add to `test/controllers/admin/stage_templates_controller_test.rb`, inside the existing test class (this file already has `setup { @project_type = project_types(:instalaciones) }`):

```ruby
  test "reorder updates position according to the submitted id order" do
    entrega = stage_templates(:entrega)
    diseno = stage_templates(:diseno_aprobacion)

    patch reorder_admin_project_type_stage_templates_path(@project_type), params: { ids: [entrega.id, diseno.id] }, as: :json
    assert_response :success

    assert_equal 0, entrega.reload.position
    assert_equal 1, diseno.reload.position
  end
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `bin/rails test test/controllers/admin/field_definitions_controller_test.rb test/controllers/admin/stage_templates_controller_test.rb`
Expected: FAIL — routing error (`reorder` action doesn't exist yet).

- [ ] **Step 4: Implement `Admin::FieldDefinitionsController#reorder`**

Edit `app/controllers/admin/field_definitions_controller.rb` — add this public method, after `destroy`:

```ruby
  def reorder
    Array(params[:ids]).each_with_index do |id, index|
      @project_type.field_definitions.where(id: id).update_all(position: index)
    end
    head :ok
  end
```

- [ ] **Step 5: Implement `Admin::StageTemplatesController#reorder`**

Edit `app/controllers/admin/stage_templates_controller.rb` — add this public method, after `destroy`:

```ruby
  def reorder
    Array(params[:ids]).each_with_index do |id, index|
      @project_type.stage_templates.where(id: id).update_all(position: index)
    end
    head :ok
  end
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `bin/rails test test/controllers/admin/field_definitions_controller_test.rb test/controllers/admin/stage_templates_controller_test.rb`
Expected: PASS (all tests)

- [ ] **Step 7: Run the full suite**

Run: `bin/rails test`
Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add config/routes.rb app/controllers/admin/field_definitions_controller.rb \
  app/controllers/admin/stage_templates_controller.rb \
  test/controllers/admin/field_definitions_controller_test.rb test/controllers/admin/stage_templates_controller_test.rb
git commit -m "Add reorder endpoints for Campos and Subprocesos"
```

---

### Task 2: Drag handles + JS in the view

**Files:**
- Modify: `app/views/admin/project_types/show.html.erb`
- Modify: `test/controllers/admin/project_types_controller_test.rb`

**Interfaces:**
- Consumes: `reorder_admin_project_type_field_definitions_path`/`reorder_admin_project_type_stage_templates_path` (Task 1, already committed).
- Produces: nothing consumed by a later task — this is the last task in the plan.

- [ ] **Step 1: Write the failing tests**

Add to `test/controllers/admin/project_types_controller_test.rb`, inside the existing test class:

```ruby
  test "show renders a drag handle and data-id for each field definition and stage template" do
    project_type = project_types(:instalaciones)
    field = field_definitions(:cliente)
    stage = stage_templates(:entrega)

    get admin_project_type_path(project_type)
    assert_response :success
    assert_select "#field-definitions-list li[data-id=?] .drag-handle", field.id.to_s
    assert_select "#stage-templates-list li[data-id=?] .drag-handle", stage.id.to_s
  end

  test "show wires the drag-reorder script to the correct endpoints" do
    project_type = project_types(:instalaciones)
    get admin_project_type_path(project_type)
    assert_response :success
    assert_match(/initDragReorder\("field-definitions-list",\s*"#{Regexp.escape(reorder_admin_project_type_field_definitions_path(project_type))}"\)/, response.body)
    assert_match(/initDragReorder\("stage-templates-list",\s*"#{Regexp.escape(reorder_admin_project_type_stage_templates_path(project_type))}"\)/, response.body)
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/controllers/admin/project_types_controller_test.rb`
Expected: FAIL — no `data-id`, no `.drag-handle`, no `initDragReorder` script exist yet.

- [ ] **Step 3: Replace `admin/project_types/show.html.erb` in full**

```erb
<h1><%= @project_type.name %></h1>
<%= link_to "Editar", edit_admin_project_type_path(@project_type), class: "btn btn-outline-secondary btn-sm mb-3" %>

<div class="card mb-4">
  <div class="card-header">Campos</div>
  <div class="card-body">
    <%= link_to "Nuevo campo", new_admin_project_type_field_definition_path(@project_type), class: "btn btn-primary btn-sm mb-2" %>
    <ul class="list-group list-group-flush" id="field-definitions-list">
      <% @project_type.field_definitions.each do |field| %>
        <li class="list-group-item d-flex justify-content-between align-items-center" data-id="<%= field.id %>">
          <span>
            <span class="drag-handle me-2" draggable="true" style="cursor: grab;">⠿</span>
            <%= field.label %> (<%= field.data_type_label %>)
          </span>
          <span>
            <%= link_to "Editar", edit_admin_project_type_field_definition_path(@project_type, field), class: "btn btn-outline-secondary btn-sm" %>
            <%= button_to "Eliminar", admin_project_type_field_definition_path(@project_type, field), method: :delete,
                  class: "btn btn-outline-danger btn-sm", form: { style: "display:inline-block", onsubmit: "return confirm('¿Eliminar campo?')" } %>
          </span>
        </li>
      <% end %>
    </ul>
  </div>
</div>

<div class="card mb-4">
  <div class="card-header">Subprocesos</div>
  <div class="card-body">
    <%= link_to "Nuevo subproceso", new_admin_project_type_stage_template_path(@project_type), class: "btn btn-primary btn-sm mb-2" %>
    <ol class="list-group list-group-numbered list-group-flush" id="stage-templates-list">
      <% @project_type.stage_templates.each do |stage| %>
        <li class="list-group-item d-flex justify-content-between align-items-center" data-id="<%= stage.id %>">
          <span>
            <span class="drag-handle me-2" draggable="true" style="cursor: grab;">⠿</span>
            <%= stage.name %>
          </span>
          <span>
            <%= link_to "Editar", edit_admin_project_type_stage_template_path(@project_type, stage), class: "btn btn-outline-secondary btn-sm" %>
            <%= button_to "Eliminar", admin_project_type_stage_template_path(@project_type, stage), method: :delete,
                  class: "btn btn-outline-danger btn-sm", form: { style: "display:inline-block", onsubmit: "return confirm('¿Eliminar subproceso?')" } %>
          </span>
        </li>
      <% end %>
    </ol>
  </div>
</div>

<script>
  function initDragReorder(listId, url) {
    var list = document.getElementById(listId);
    if (!list) return;
    var dragging;

    list.addEventListener("dragstart", function (e) {
      if (!e.target.classList.contains("drag-handle")) return;
      dragging = e.target.closest("li");
      dragging.classList.add("opacity-50");
    });

    list.addEventListener("dragend", function () {
      if (dragging) dragging.classList.remove("opacity-50");
    });

    list.addEventListener("dragover", function (e) {
      e.preventDefault();
      if (!dragging) return;
      var target = e.target.closest("li");
      if (!target || target === dragging) return;
      var rect = target.getBoundingClientRect();
      var after = (e.clientY - rect.top) > rect.height / 2;
      list.insertBefore(dragging, after ? target.nextSibling : target);
    });

    list.addEventListener("drop", function (e) {
      e.preventDefault();
      if (!dragging) return;
      var ids = Array.from(list.querySelectorAll("li[data-id]")).map(function (li) { return li.dataset.id; });
      dragging = null;
      fetch(url, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
        },
        body: JSON.stringify({ ids: ids })
      });
    });
  }

  document.addEventListener("DOMContentLoaded", function () {
    initDragReorder("field-definitions-list", "<%= reorder_admin_project_type_field_definitions_path(@project_type) %>");
    initDragReorder("stage-templates-list", "<%= reorder_admin_project_type_stage_templates_path(@project_type) %>");
  });
</script>
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bin/rails test test/controllers/admin/project_types_controller_test.rb`
Expected: PASS (all tests)

- [ ] **Step 5: Run the full suite**

Run: `bin/rails test`
Expected: PASS

- [ ] **Step 6: Manual verification**

Run: `bin/rails server`, go to Administración → "Instalaciones":
- Confirm each Campo/Subproceso row shows a small "⠿" handle.
- Drag a row by its handle to a new position — confirm it reorders live while dragging.
- Drop it — confirm the order persists after reloading the page.
- Confirm clicking "Editar"/"Eliminar" on any row still works normally (doesn't accidentally start a drag).

- [ ] **Step 7: Commit**

```bash
git add app/views/admin/project_types/show.html.erb test/controllers/admin/project_types_controller_test.rb
git commit -m "Add native drag-and-drop reordering UI for Campos and Subprocesos"
```

---

## Final verification

- [ ] Run `bin/rails test` once more — expect a clean pass.
