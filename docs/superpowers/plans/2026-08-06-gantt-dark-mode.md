# Gantt Dark Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Both Gantt charts (project-detail and project-list) follow the app's dark mode, using frappe-gantt 1.2.2's own built-in dark palette.

**Architecture:** Frappe Gantt's CSS already defines a full dark theme keyed on `html[data-theme="dark"]` — a different attribute than the `data-bs-theme` the app already toggles for Bootstrap. Setting `data-theme` alongside `data-bs-theme` everywhere the app sets the latter activates frappe-gantt's dark palette with zero new CSS for the chart internals. One custom override in `gantt.css` (the progress-bar overlay, hardcoded black) gets an explicit dark counterpart.

**Tech Stack:** Rails 7.2 (ERB), Stimulus, Frappe Gantt 1.2.2 (CDN), Minitest.

## Global Constraints

- Do not invent a custom dark palette for the Gantt grid/header/popup — use frappe-gantt's own `html[data-theme="dark"]` CSS, already loaded via the CDN stylesheet.
- Do not touch `--bar-fill` (per-stage/per-responsible bar color) or any other rule in `gantt.css` besides the progress-overlay dark counterpart.
- Both the `theme_controller.js` toggle and the anti-flash inline script in `application.html.erb` must set `data-theme` with the exact same value as `data-bs-theme`, every time either is set — a mismatch would flash the Gantt in the wrong theme on load or leave it stuck after a toggle.

---

### Task 1: Sync `data-theme` with `data-bs-theme`

**Files:**
- Modify: `app/javascript/controllers/theme_controller.js`
- Modify: `app/views/layouts/application.html.erb:12`
- Test: `test/controllers/navbar_test.rb`

**Interfaces:**
- Produces: `<html>` always carries `data-theme` equal to `data-bs-theme` (`"light"` or `"dark"`), both on first paint (inline script) and after every toggle (`theme_controller.js#apply`). Task 2 doesn't depend on this — it's a separate CSS-only override — but both tasks together are what makes the Gantt fully dark-mode aware.

- [ ] **Step 1: Write the failing tests**

Add to `test/controllers/navbar_test.rb`, inside the `NavbarTest` class:

```ruby
  test "layout's anti-flash script sets data-theme alongside data-bs-theme, for frappe-gantt" do
    sign_in users(:juan)
    get root_path
    follow_redirect!
    assert_response :success
    assert_match(/document\.documentElement\.dataset\.bsTheme = document\.documentElement\.dataset\.theme = /, response.body)
  end

  test "theme controller sets data-theme alongside data-bs-theme, for frappe-gantt" do
    source = Rails.root.join("app/javascript/controllers/theme_controller.js").read
    assert_match(/setAttribute\("data-theme",\s*theme\)/, source)
  end
```

- [ ] **Step 2: Run both to confirm they fail**

Run: `bin/rails test test/controllers/navbar_test.rb -n test_layout_s_anti_flash_script_sets_data_theme_alongside_data_bs_theme_for_frappe_gantt -n test_theme_controller_sets_data_theme_alongside_data_bs_theme_for_frappe_gantt`
Expected: both FAIL — neither file sets `data-theme` yet.

- [ ] **Step 3: Update the anti-flash inline script**

In `app/views/layouts/application.html.erb`, replace line 12:

```erb
<script>document.documentElement.dataset.bsTheme = document.documentElement.dataset.theme = (localStorage.getItem("theme") || (matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light"))</script>
```

(Chained assignment: computes the theme once, assigns it to both `dataset.bsTheme` and `dataset.theme`.)

- [ ] **Step 4: Update the theme controller**

In `app/javascript/controllers/theme_controller.js`, replace the `apply(theme)` method:

```javascript
  apply(theme) {
    document.documentElement.setAttribute("data-bs-theme", theme)
    document.documentElement.setAttribute("data-theme", theme)
    if (this.hasIconTarget) {
      this.iconTarget.textContent = theme === "dark" ? "☀" : "☾"
    }
  }
```

- [ ] **Step 5: Run both tests to confirm they pass**

Run: `bin/rails test test/controllers/navbar_test.rb -n test_layout_s_anti_flash_script_sets_data_theme_alongside_data_bs_theme_for_frappe_gantt -n test_theme_controller_sets_data_theme_alongside_data_bs_theme_for_frappe_gantt`
Expected: both PASS

- [ ] **Step 6: Run the full navbar test file**

Run: `bin/rails test test/controllers/navbar_test.rb`
Expected: all PASS, 0 failures.

- [ ] **Step 7: Commit**

```bash
git add app/javascript/controllers/theme_controller.js app/views/layouts/application.html.erb test/controllers/navbar_test.rb
git commit -m "Sincronizar data-theme con data-bs-theme para el modo oscuro nativo de frappe-gantt"
```

---

### Task 2: Dark-mode progress overlay + manual verification

**Files:**
- Modify: `app/assets/stylesheets/gantt.css`
- Test: `test/controllers/projects_controller_test.rb`

**Interfaces:**
- Consumes: `data-bs-theme` on `<html>` (already existed before this plan; Task 1 additionally keeps `data-theme` in sync, which is what activates frappe-gantt's own dark palette — this task's CSS selector keys off `data-bs-theme` directly, matching every other dark-mode override already in `application.css`).
- Produces: no new interface — last task of this plan.

- [ ] **Step 1: Write the failing test**

Add to `test/controllers/projects_controller_test.rb`, right after the existing test at line ~890 (`"index's Gantt overrides the progress-bar fill for visibility against custom bar colors"`, which asserts the light-mode `rgba(0, 0, 0, 0.25)` rule):

```ruby
  test "index's Gantt progress overlay switches to a light fill in dark mode for contrast" do
    Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    get project_type_projects_path(project_types(:instalaciones).slug)
    assert_response :success
    gantt_css = Rails.root.join("app/assets/stylesheets/gantt.css").read
    assert_match(/\[data-bs-theme="dark"\]\s*\.bar-progress\s*\{\s*\n\s*fill:\s*rgba\(255,\s*255,\s*255,\s*0\.25\);?\s*\n\s*\}/, gantt_css)
  end
```

- [ ] **Step 2: Run to confirm it fails**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n test_index_s_Gantt_progress_overlay_switches_to_a_light_fill_in_dark_mode_for_contrast`
Expected: FAIL — no `[data-bs-theme="dark"] .bar-progress` rule exists yet.

- [ ] **Step 3: Add the dark-mode rule**

In `app/assets/stylesheets/gantt.css`, add right after the existing `.gantt .bar-progress { fill: rgba(0, 0, 0, 0.25); }` block:

```css
[data-bs-theme="dark"] .gantt .bar-progress {
  fill: rgba(255, 255, 255, 0.25);
}
```

- [ ] **Step 4: Run the test to confirm it passes**

Run: `bin/rails test test/controllers/projects_controller_test.rb -n test_index_s_Gantt_progress_overlay_switches_to_a_light_fill_in_dark_mode_for_contrast`
Expected: PASS

- [ ] **Step 5: Run the full controller test file**

Run: `bin/rails test test/controllers/projects_controller_test.rb`
Expected: all PASS, 0 failures — in particular the two pre-existing tests asserting the light-mode `rgba(0, 0, 0, 0.25)` rule (around lines 331 and 890) must still pass, since this task only adds a new rule, it doesn't touch the existing one.

- [ ] **Step 6: Manual verification in browser**

Run: `bin/rails server`, sign in, and check both Gantt charts in both themes:
- Open a project's page (`gantt-stage-editor`) in light mode — grid, header, and progress overlay look as before.
- Toggle to dark mode (navbar button) on that same page — the Gantt's background, grid lines, header, and popups switch to frappe-gantt's dark palette (no white background left behind), and the progress overlay on each bar stays visibly lighter than the bar itself.
- Open a project type's listing page (`gantt-project-list`) in both themes — same check: dark background/grid/header, progress overlay visible.
- Confirm the Día/Semana/Mes buttons and the sort toggle (from the previous feature) still work normally in both themes.

Stop the server after checking.

- [ ] **Step 7: Commit**

```bash
git add app/assets/stylesheets/gantt.css test/controllers/projects_controller_test.rb
git commit -m "Agregar overlay de progreso visible en dark mode para el Gantt"
```
