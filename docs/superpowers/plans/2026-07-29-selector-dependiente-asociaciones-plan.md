# Selector dependiente en "Vincular proyecto existente" Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In the "Asociaciones" card's "vincular a proyecto existente" form, narrow the "Proyecto" select to only the type expected by whichever "Tipo de asociación" is chosen — replacing the deliberate simplification called out in a `ponytail:` comment in `projects/show.html.erb`.

**Architecture:** Pure view/JS change. Each `<option>` in both selects gains a `data-*` attribute (the project's own type id for "Proyecto", the *other side's* expected type id for "Tipo de asociación"). A small vanilla-JS listener hides non-matching options when the association type changes — no new dependency, matches the style of existing inline scripts in this app (e.g. the stage-table duration calculator).

**Tech Stack:** Rails 7.2, Minitest with fixtures, vanilla JS.

## Global Constraints

- No new JS dependency, no DB/model changes.
- Server-side validation in `ProjectAssociation`/`ProjectAssociationsController` (already in place) stays the actual source of truth — this is a UX narrowing, not a new validation layer.
- The app already restricts itself to modern browsers (`allow_browser versions: :modern` in `ApplicationController`), so using the `hidden` property on `<option>` elements is safe.

---

### Task 1: Dependent "Proyecto" select

**Files:**
- Modify: `app/views/projects/show.html.erb`
- Test: `test/controllers/projects_controller_test.rb`

**Interfaces:**
- None — pure view/JS change, no new routes or methods.

- [ ] **Step 1: Write the failing tests**

Add to `test/controllers/projects_controller_test.rb`:

```ruby
  test "show's link-existing-project form tags each option with its project type, for JS filtering" do
    other_type = ProjectType.create!(name: "Caso de Servicio", slug: "caso-de-servicio")
    association = ProjectTypeAssociation.create!(from_project_type: other_type, to_project_type: project_types(:instalaciones), label: "Caso de servicio")
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    caso = Project.create!(project_type: other_type, name: "Ticket 1", custom_fields: {})

    get project_path(project)
    assert_response :success
    assert_select "select#project_association_project_type_association_id option[value=?][data-other-project-type-id=?]",
      association.id.to_s, other_type.id.to_s
    assert_select "select#project_association_other_project_id option[value=?][data-project-type-id=?]",
      caso.id.to_s, other_type.id.to_s
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n "/JS filtering/"`
Expected: FAIL — neither select's options carry these `data-*` attributes yet.

- [ ] **Step 3: Read the current form block**

Read `app/views/projects/show.html.erb` in full first — find the "vincular a proyecto existente" `form_with` block (it currently has a `ponytail:` comment above it and two `f.collection_select` calls for `:project_type_association_id` and `:other_project_id`).

- [ ] **Step 4: Replace the two selects and remove the now-obsolete `ponytail:` comment**

Replace:

```erb
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
```

with:

```erb
        <%= form_with url: project_project_associations_path(@project), method: :post, scope: :project_association, class: "row g-2 mb-3" do |f| %>
          <div class="col-auto">
            <%
              applicable_associations = ProjectTypeAssociation.where(from_project_type: @project.project_type).or(ProjectTypeAssociation.where(to_project_type: @project.project_type))
              association_options = applicable_associations.map do |a|
                other_type_id = a.from_project_type_id == @project.project_type_id ? a.to_project_type_id : a.from_project_type_id
                [a.label, a.id, { data: { other_project_type_id: other_type_id } }]
              end
            %>
            <%= f.select :project_type_association_id, options_for_select(association_options),
                  { include_blank: "Tipo de asociación" }, class: "form-select", id: "project_association_project_type_association_id" %>
          </div>
          <div class="col-auto">
            <%
              project_options = Project.where.not(id: @project.id).order(:name).map { |p| [p.name, p.id, { data: { project_type_id: p.project_type_id } }] }
            %>
            <%= f.select :other_project_id, options_for_select(project_options),
                  { include_blank: "Proyecto" }, class: "form-select", id: "project_association_other_project_id" %>
          </div>
          <div class="col-auto">
            <%= f.submit "Vincular", class: "btn btn-primary" %>
          </div>
        <% end %>

        <script>
          document.addEventListener("DOMContentLoaded", function () {
            var typeSelect = document.getElementById("project_association_project_type_association_id");
            var otherSelect = document.getElementById("project_association_other_project_id");
            if (!typeSelect || !otherSelect) return;

            function filterOptions() {
              var selected = typeSelect.options[typeSelect.selectedIndex];
              var otherProjectTypeId = selected ? selected.dataset.otherProjectTypeId : null;
              Array.from(otherSelect.options).forEach(function (option) {
                if (!option.value) return;
                option.hidden = !!otherProjectTypeId && option.dataset.projectTypeId !== otherProjectTypeId;
              });
              if (otherSelect.selectedOptions[0] && otherSelect.selectedOptions[0].hidden) {
                otherSelect.value = "";
              }
            }

            typeSelect.addEventListener("change", filterOptions);
            filterOptions();
          });
        </script>
```

(Note: `f.select`'s generated element `id` defaults to `project_association_project_type_association_id`/`project_association_other_project_id` already, given `scope: :project_association` — the explicit `id:` options above just make that name visible/pinned in this diff; they are not changing the pre-existing id, only making Task 1's test assertions self-documenting. Verify this matches what the form actually renders before assuming — if Rails already produces those exact ids without the explicit option, the explicit `id:` is redundant but harmless.)

- [ ] **Step 5: Run tests to verify they pass**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: PASS

- [ ] **Step 6: Run the full suite**

Run: `bin/rails test`
Expected: PASS, no regressions — in particular re-check any existing test asserting on the old `f.collection_select`-generated markup for these two fields still passes with the new `f.select` + `options_for_select` markup (they should be byte-equivalent for the `<option>` list itself, only adding `data-*` attributes).

- [ ] **Step 7: Commit**

```bash
git add app/views/projects/show.html.erb test/controllers/projects_controller_test.rb
git commit -m "Filter the existing-project select by the chosen association type"
```
