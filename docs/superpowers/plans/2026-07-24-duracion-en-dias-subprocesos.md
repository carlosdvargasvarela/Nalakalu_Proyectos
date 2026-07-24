# Duración (días) para completar la fecha Fin — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Duración (días)" input next to each stage's Inicio/Fin fields that auto-fills Fin = Inicio + duración, purely client-side.

**Architecture:** A single view/JS change to the shared `_stage_table.html.erb` partial (used by both `projects#show` and `projects#tracker`) — one new unnamed `<input>` column plus a small vanilla JS listener. No controller, model, or route changes.

**Tech Stack:** Rails 7.2.3 view code, vanilla JS (no Turbo/Stimulus/jQuery, consistent with the rest of this app), Minitest.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-24-duracion-en-dias-subprocesos-design.md`.
- The Duración input has NO `name` attribute — it must never be submitted to the server or persisted anywhere. No migration, no new column.
- One-directional only: typing into Duración recalculates Fin. Editing Fin afterward does NOT update Duración. Duración is never pre-filled from existing Inicio/Fin values on page load.
- The date math must use `T00:00:00` when parsing to avoid a timezone-induced off-by-one-day shift, and `setDate` (not manual month/day arithmetic) so month/year rollovers are handled correctly.
- This plan touches only `_stage_table.html.erb` (shared by `show` and `tracker`) — no other view.

---

## File Structure

- Modify `app/views/projects/_stage_table.html.erb` — add the Duración column and the JS listener.
- Modify `test/controllers/projects_controller_test.rb` — add a rendering test for the new column.

---

### Task 1: Duración (días) column with auto-fill JS

**Files:**
- Modify: `app/views/projects/_stage_table.html.erb` (entire file).
- Test: `test/controllers/projects_controller_test.rb`.

**Interfaces:** None — this is a self-contained view/JS change with no controller or model involvement, and no other task in this plan depends on it (it's the only task).

- [ ] **Step 1: Write the failing test**

Add to `test/controllers/projects_controller_test.rb` (near the other stage-table test, `"show renders an editable table row for each stage"`):

```ruby
  test "show's stage table renders a Duración (días) input with no name attribute, per stage" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_path(project)
    assert_response :success
    assert_select ".stage-table th", text: "Duración (días)"
    assert_select ".stage-table input.duracion-input", count: project.project_stages.count
    assert_select ".stage-table input.duracion-input[name]", count: 0
  end

  test "tracker's stage table renders a Duración (días) input with no name attribute, per stage" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get tracker_projects_path
    assert_response :success
    assert_select ".stage-table th", text: "Duración (días)"
    assert_select ".stage-table input.duracion-input", count: project.project_stages.count
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n "/Duración/"`
Expected: FAIL — no "Duración (días)" column exists yet.

- [ ] **Step 3: Add the column and the JS**

Replace the entire content of `app/views/projects/_stage_table.html.erb`:

```erb
<%= form_with model: project do |f| %>
  <table class="table table-sm table-bordered mb-0 stage-table">
    <thead>
      <tr><th>Etapa</th><th>Inicio</th><th>Fin</th><th>% Avance</th><th>Estado</th></tr>
    </thead>
    <tbody>
      <%= f.fields_for :project_stages, project.project_stages.includes(:stage_template).order(:id) do |sf| %>
        <tr id="stage-<%= sf.object.id %>">
          <td><%= sf.object.name %></td>
          <td><%= sf.hidden_field :id %><%= sf.date_field :start_date, class: "form-control form-control-sm fecha-input" %></td>
          <td><%= sf.date_field :end_date, class: "form-control form-control-sm fecha-input" %></td>
          <td><%= sf.number_field :progress_percent, min: 0, max: 100, class: "form-control form-control-sm avance-input" %></td>
          <td>
            <%= progress_status_badge(sf.object.progress_status) %>
            <%= overdue_badge if sf.object.overdue? %>
          </td>
        </tr>
      <% end %>
    </tbody>
  </table>
  <%= f.submit "Guardar cambios", class: "btn btn-primary btn-sm mt-3" %>
<% end %>
```

with:

```erb
<%= form_with model: project do |f| %>
  <table class="table table-sm table-bordered mb-0 stage-table">
    <thead>
      <tr><th>Etapa</th><th>Inicio</th><th>Fin</th><th>Duración (días)</th><th>% Avance</th><th>Estado</th></tr>
    </thead>
    <tbody>
      <%= f.fields_for :project_stages, project.project_stages.includes(:stage_template).order(:id) do |sf| %>
        <tr id="stage-<%= sf.object.id %>">
          <td><%= sf.object.name %></td>
          <td><%= sf.hidden_field :id %><%= sf.date_field :start_date, class: "form-control form-control-sm fecha-input" %></td>
          <td><%= sf.date_field :end_date, class: "form-control form-control-sm fecha-input" %></td>
          <td><input type="number" min="1" class="form-control form-control-sm duracion-input"></td>
          <td><%= sf.number_field :progress_percent, min: 0, max: 100, class: "form-control form-control-sm avance-input" %></td>
          <td>
            <%= progress_status_badge(sf.object.progress_status) %>
            <%= overdue_badge if sf.object.overdue? %>
          </td>
        </tr>
      <% end %>
    </tbody>
  </table>
  <%= f.submit "Guardar cambios", class: "btn btn-primary btn-sm mt-3" %>
<% end %>

<script>
  document.querySelectorAll(".stage-table tbody tr").forEach(function (row) {
    var duracionInput = row.querySelector(".duracion-input");
    var startInput = row.querySelector("input[name*='[start_date]']");
    var endInput = row.querySelector("input[name*='[end_date]']");
    if (!duracionInput || !startInput || !endInput) return;

    duracionInput.addEventListener("input", function () {
      var days = parseInt(duracionInput.value, 10);
      if (!startInput.value || isNaN(days)) return;
      var start = new Date(startInput.value + "T00:00:00");
      start.setDate(start.getDate() + days);
      endInput.value = start.toISOString().slice(0, 10);
    });
  });
</script>
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: all PASS.

- [ ] **Step 5: Run the full suite to check for regressions elsewhere**

Run: `bin/rails test`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add app/views/projects/_stage_table.html.erb test/controllers/projects_controller_test.rb
git commit -m "Add Duración (días) helper to auto-fill a stage's Fin date"
```

---

## Final Verification

- [ ] Run the full test suite: `bin/rails test`
- [ ] Expected: all tests pass, no regressions anywhere else in the app.
