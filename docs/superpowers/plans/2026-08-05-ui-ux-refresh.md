# UI/UX Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Modernize Nalakalú's visual style (colors, typography, component polish) and add a manual light/dark toggle, by overriding Bootstrap 5.3's own `--bs-*` custom properties — no new CSS framework, no component rewrites.

**Architecture:** All color/typography changes live in `app/assets/stylesheets/application.css` as `:root` and `[data-bs-theme="dark"]` custom-property overrides, which Bootstrap's existing components (`.btn`, `.card`, `.table`, `.badge`, `.form-control`) already consume. A new Stimulus controller (`theme_controller.js`) flips `data-bs-theme` on `<html>` and persists the choice in `localStorage`, wired to a new toggle button in `_navbar.html.erb`.

**Tech Stack:** Rails 7, Bootstrap 5.3.3 (CDN), Stimulus, Turbo, Minitest (`ActionDispatch::IntegrationTest`).

## Global Constraints

- No new dependencies, no framework migration, no Gemfile/importmap changes — spec: docs/superpowers/specs/2026-08-05-ui-ux-refresh-design.md.
- `gantt.css` is not touched except via automatic inheritance of `--bs-*` variables — its bar colors come from JS/data, not CSS.
- Contrast must stay ≥ 4.5:1 in both light and dark — use the exact hex values from the spec's palette table, don't improvise new ones.
- Single font family (Inter) for both headings and body via `--bs-body-font-family`.

---

### Task 1: Brand colors and typography (light mode)

**Files:**
- Modify: `app/assets/stylesheets/application.css`

**Interfaces:**
- Produces: `--bs-primary`, `--bs-primary-rgb`, `--bs-success`, `--bs-danger`, `--bs-body-bg`, `--bs-body-color`, `--bs-border-color`, `--bs-tertiary-bg`, `--bs-body-font-family` redefined under `:root`. Task 2 adds the `[data-bs-theme="dark"]` counterparts for the same variable names.

- [ ] **Step 1: Replace the `:root` block with the full light-mode palette + font**

Replace the existing `:root { ... }` block (lines 17-25) with:

```css
@import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap');

:root {
  --bs-primary: #2563EB;
  --bs-primary-rgb: 37, 99, 235;
  --bs-success: #059669;
  --bs-danger: #DC2626;
  --bs-body-bg: #F8FAFC;
  --bs-body-color: #1E293B;
  --bs-border-color: #E2E8F0;
  --bs-tertiary-bg: #E9EFF8;
  --bs-body-font-family: "Inter", system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
  --bs-link-color: var(--bs-primary);
  --bs-link-hover-color: #1E40AF;
  --bs-border-radius: 0.5rem;
  --bs-border-radius-sm: 0.35rem;
  --bs-border-radius-lg: 0.65rem;
}
```

This drops the old `--bs-primary: #2c3e50` navy and the hardcoded hover color, replacing them with the spec's blue palette. `--bs-link-hover-color` is a manually darkened shade of the new primary (no separate spec token for it, matching how the old CSS handled hover).

- [ ] **Step 2: Update `.btn-primary` hover color to match**

The existing `.btn-primary` block (lines 27-32) hardcodes `#1a252f` (the old navy's hover shade). Replace it:

```css
.btn-primary {
  --bs-btn-bg: var(--bs-primary);
  --bs-btn-border-color: var(--bs-primary);
  --bs-btn-hover-bg: #1E40AF;
  --bs-btn-hover-border-color: #1E40AF;
}
```

- [ ] **Step 3: Verify the app boots and renders with the new palette**

Run: `bin/rails server` (or your existing dev-server command), open `http://localhost:3000`, sign in, and confirm:
- Primary buttons and links are blue (`#2563EB`), not navy.
- Body background is off-white (`#F8FAFC`), text is dark slate.
- Font is Inter (check via browser devtools computed styles on `<body>`).

Stop the server after checking (Ctrl-C).

- [ ] **Step 4: Commit**

```bash
git add app/assets/stylesheets/application.css
git commit -m "Actualizar paleta de color y tipografía base (Inter, azul)"
```

---

### Task 2: Dark mode toggle

**Files:**
- Modify: `app/assets/stylesheets/application.css`
- Modify: `app/views/layouts/_navbar.html.erb`
- Create: `app/javascript/controllers/theme_controller.js`
- Modify: `test/controllers/navbar_test.rb`

**Interfaces:**
- Consumes: `--bs-primary`, `--bs-success`, `--bs-danger`, `--bs-body-bg`, `--bs-body-color`, `--bs-border-color`, `--bs-tertiary-bg` (Task 1) — dark values are added as a parallel block, same variable names.
- Produces: `data-controller="theme"` root element with `data-action="click->theme#toggle"` button (`data-theme-target="icon"` on the icon span), and `data-bs-theme` attribute on `<html>`. Task 3 does not depend on this controller.

- [ ] **Step 1: Add dark-mode variable overrides to `application.css`**

Append after the `:root` block from Task 1:

```css
[data-bs-theme="dark"] {
  --bs-primary: #3B82F6;
  --bs-primary-rgb: 59, 130, 246;
  --bs-success: #10B981;
  --bs-danger: #EF4444;
  --bs-body-bg: #0F172A;
  --bs-body-color: #F1F5F9;
  --bs-border-color: #334155;
  --bs-tertiary-bg: #334155;
  --bs-link-color: var(--bs-primary);
  --bs-link-hover-color: #93C5FD;
}
```

- [ ] **Step 2: Write the theme controller**

Create `app/javascript/controllers/theme_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

const STORAGE_KEY = "theme"

// Toggles data-bs-theme on <html> between "light" and "dark", persisting the
// choice in localStorage. Falls back to the OS preference (prefers-color-scheme)
// the first time, before any manual choice has been made.
export default class extends Controller {
  static targets = ["icon"]

  connect() {
    const stored = localStorage.getItem(STORAGE_KEY)
    const theme = stored || (window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light")
    this.apply(theme)
  }

  toggle() {
    const current = document.documentElement.getAttribute("data-bs-theme")
    const next = current === "dark" ? "light" : "dark"
    localStorage.setItem(STORAGE_KEY, next)
    this.apply(next)
  }

  apply(theme) {
    document.documentElement.setAttribute("data-bs-theme", theme)
    if (this.hasIconTarget) {
      this.iconTarget.textContent = theme === "dark" ? "☀" : "☾"
    }
  }
}
```

- [ ] **Step 3: Wire the toggle button into the navbar**

In `app/views/layouts/_navbar.html.erb`, wrap the session `<div class="navbar-nav">` block (lines 17-24) with the theme controller and add a toggle button before it:

```erb
<div class="navbar-nav" data-controller="theme">
  <button type="button" class="btn btn-outline-secondary btn-sm me-2" data-action="click->theme#toggle" aria-label="Cambiar tema claro/oscuro">
    <span data-theme-target="icon">☾</span>
  </button>
  <% if user_signed_in? %>
    <span class="navbar-text me-3"><%= current_user.email %></span>
    <%= button_to "Cerrar sesión", destroy_user_session_path, method: :delete, class: "btn btn-outline-secondary btn-sm" %>
  <% else %>
    <%= link_to "Iniciar sesión", new_user_session_path, class: "btn btn-outline-primary btn-sm me-2" %>
  <% end %>
</div>
```

- [ ] **Step 4: Write the failing test**

Add to `test/controllers/navbar_test.rb`, inside the `NavbarTest` class:

```ruby
  test "navbar includes the theme toggle button" do
    sign_in users(:juan)
    get root_path
    follow_redirect!
    assert_response :success
    assert_select "nav button[data-action=?]", "click->theme#toggle"
  end
```

- [ ] **Step 5: Run the test to verify it fails**

Run: `bin/rails test test/controllers/navbar_test.rb -n test_navbar_includes_the_theme_toggle_button`
Expected: FAIL (button doesn't exist yet) — if Steps 1-3 above weren't applied yet. Since this plan has you apply the markup before the test in Steps 1-3, instead run it now to confirm it currently PASSES, then temporarily comment out the button in `_navbar.html.erb` and re-run to see it FAIL, then uncomment. This confirms the test actually exercises the markup.

- [ ] **Step 6: Run the full test to confirm it passes with the real markup restored**

Run: `bin/rails test test/controllers/navbar_test.rb`
Expected: all tests PASS, including the new one.

- [ ] **Step 7: Manual verification in browser**

Run: `bin/rails server`, open the app, sign in, and confirm:
- Toggle button appears in the navbar with a ☾ icon.
- Clicking it switches the whole page to dark colors (`#0F172A` background) and the icon changes to ☀.
- Reloading the page keeps the chosen theme (persisted via `localStorage`).
- With `localStorage` cleared and OS set to dark mode, the app loads in dark mode by default.

Stop the server after checking.

- [ ] **Step 8: Commit**

```bash
git add app/assets/stylesheets/application.css app/views/layouts/_navbar.html.erb app/javascript/controllers/theme_controller.js test/controllers/navbar_test.rb
git commit -m "Añadir modo oscuro con toggle manual (data-bs-theme)"
```

---

### Task 3: Component depth pass (cards, tables, badges, forms)

**Files:**
- Modify: `app/assets/stylesheets/application.css`

**Interfaces:**
- Consumes: `--bs-primary`, `--bs-border-color`, `--bs-tertiary-bg`, `--bs-border-radius*` (Tasks 1-2).

- [ ] **Step 1: Refine card, table, badge, and form styling**

Replace the existing `.card`, `.card-header`, and `.nav-tabs .nav-link.active` blocks (previously lines 50-64) with:

```css
.card {
  box-shadow: 0 0.25rem 0.75rem rgba(15, 23, 42, 0.08);
  border: 1px solid var(--bs-border-color);
}

.card-header {
  background-color: var(--bs-tertiary-bg);
  font-weight: 600;
}

.nav-tabs .nav-link.active {
  color: var(--bs-primary);
  border-color: var(--bs-border-color) var(--bs-border-color) var(--bs-body-bg);
  font-weight: 600;
}

.table {
  --bs-table-border-color: var(--bs-border-color);
}

.table thead th {
  font-weight: 600;
  color: var(--bs-body-color);
}

.badge {
  font-weight: 500;
  letter-spacing: 0.01em;
}

.form-control:focus,
.form-select:focus {
  border-color: var(--bs-primary);
  box-shadow: 0 0 0 0.2rem rgba(var(--bs-primary-rgb), 0.25);
}
```

Keep the unrelated `.navbar-brand`, `.avance-input`, `.fecha-input` rules as-is (lines 34-48) — they're layout/behavior rules, not part of this color/depth pass.

- [ ] **Step 2: Manual verification in both themes**

Run: `bin/rails server`, open the app signed in as an admin (to see admin CRUD tables), and in both light and dark mode confirm:
- Cards have a visible but subtle shadow and a border matching the theme.
- Table headers are bold and readable; row borders use the theme's border color.
- Status badges (project stages, etc.) remain legible in both themes.
- Focusing a form input/select shows a blue focus ring matching `--bs-primary`.

Stop the server after checking.

- [ ] **Step 3: Run the full test suite**

Run: `bin/rails test`
Expected: all tests PASS (no test asserts on card/table/badge CSS specifically — this step guards against any markup breakage from the CSS pass, e.g. accidental selector typos affecting Capybara/assert_select lookups elsewhere).

- [ ] **Step 4: Commit**

```bash
git add app/assets/stylesheets/application.css
git commit -m "Pulir tarjetas, tablas, badges y formularios con la nueva paleta"
```
