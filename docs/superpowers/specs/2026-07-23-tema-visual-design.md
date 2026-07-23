# Tema visual propio, badges de estado en español — design

## Contexto

Tras la Ronda 1 (pantalla unificada, Gantt de solo lectura, app en español), la app sigue usando Bootstrap 5.3 sin ninguna personalización — azul por defecto, sin identidad, `app/assets/stylesheets/application.css` está vacío. Además, revisando `projects/index.html.erb` encontré un resto de la Ronda 1: `Project#status` se guarda como `"active"`/`"archived"` (inglés) y se muestra crudo tanto en la columna "Estado" de la tabla (`<%= project.status %>`, línea 86) como en las opciones del `<select>` de filtro (`form.select :status, @statuses, ...`, línea 11) — mismo tipo de hueco que cerramos con Devise, aplicado aquí al pulido visual.

## Alcance

1. **Paleta y tipografía propias** — variables CSS de Bootstrap sobrescritas en `application.css`, sin tocar la estructura HTML de ninguna vista.
2. **Badges de estado en español** — helper compartido que traduce y colorea `status`, usado en la tabla de proyectos y en las opciones del filtro.
3. **Aire/espaciado** — ajustes con clases de utilidad de Bootstrap ya usadas en el proyecto (`mb-*`, `text-muted`), sin nuevas clases CSS.

Fuera de alcance (decidido en brainstorming): reescribir el layout en tarjetas, tipografía externa (Google Fonts u otro CDN de fuentes), rediseño del Gantt.

## 1. Paleta y tipografía

`app/assets/stylesheets/application.css` (hoy vacío salvo el comentario del generador) agrega, al final:

```css
:root {
  --bs-primary: #2c3e50;
  --bs-primary-rgb: 44, 62, 80;
  --bs-link-color: #2c3e50;
  --bs-link-hover-color: #1a252f;
  --bs-border-radius: 0.5rem;
  --bs-border-radius-sm: 0.35rem;
  --bs-border-radius-lg: 0.65rem;
}

.btn-primary {
  --bs-btn-bg: var(--bs-primary);
  --bs-btn-border-color: var(--bs-primary);
  --bs-btn-hover-bg: #1a252f;
  --bs-btn-hover-border-color: #1a252f;
}

.navbar-brand {
  font-weight: 600;
  letter-spacing: 0.01em;
}
```

(Azul grafito/oscuro — profesional, neutro, funciona bien junto a los colores configurables de `StageTemplate#color` en el Gantt sin competir con ellos. `--bs-primary-rgb` se actualiza junto con `--bs-primary` porque Bootstrap deriva estados `:hover`/`:focus` y variantes `bg-primary-subtle` de la versión RGB — dejarla desincronizada rompería esas variantes aunque no se usen todavía. No se toca `--bs-body-font-family`: la pila de fuentes nativa del sistema que trae Bootstrap por defecto ya es legible y no requiere una fuente externa — cambiarla sería un rung más abajo en la escalera sin necesidad real.)

Esto no requiere cambios en ninguna vista — el `<link>` a Bootstrap ya está en `application.html.erb`, y `application.css` ya se carga después vía `stylesheet_link_tag "application"`, así que las variables sobrescritas ganan por orden de carga (confirmado: el `<link>` de Bootstrap va primero en el `<head>`, `stylesheet_link_tag "application"` después).

## 2. Badges de estado en español

`app/helpers/application_helper.rb`:

```ruby
module ApplicationHelper
  STATUS_LABELS = { "active" => "Activo", "archived" => "Archivado" }.freeze
  STATUS_BADGE_CLASSES = { "active" => "bg-success", "archived" => "bg-secondary" }.freeze

  def status_label(status)
    STATUS_LABELS.fetch(status, status)
  end

  def status_badge(status)
    tag.span(status_label(status), class: "badge #{STATUS_BADGE_CLASSES.fetch(status, 'bg-light text-dark')}")
  end
end
```

(`fetch` con default devuelve el valor crudo si algún día aparece un tercer estado no contemplado — no rompe, simplemente no lo traduce ni lo colorea, igual que el resto de la app no persigue cobertura exhaustiva de valores futuros no pedidos.)

**Uso en `projects/index.html.erb`:**

- Columna "Estado" de la tabla (línea 86): `<td><%= project.status %></td>` → `<td><%= status_badge(project.status) %></td>`.
- Opciones del `<select>` de filtro (línea 11): `form.select :status, @statuses, ...` → `form.select :status, @statuses.map { |s| [status_label(s), s] }, ...` (el `value` sigue siendo el string crudo `"active"`/`"archived"` que el controlador ya espera; solo cambia el texto mostrado).

## Testing

- Helper: `status_label`/`status_badge` — con `"active"`, `"archived"`, y un valor no contemplado (pasa tal cual, sin traducir).
- Controlador: `projects#index` — la tabla muestra el badge en español ("Activo"/"Archivado") en vez del string crudo; el `<select>` de Estado muestra las opciones en español pero conserva el `value` original (`archived`, no `Archivado`) para que el filtro siga funcionando.
- No hay test automatizado para el tema de color/tipografía (CSS puro, fuera del alcance de Minitest) — se verifica visualmente.

## Edge cases

- Un `Project#status` con un valor no traducido (ninguno existe hoy — solo `"active"`/`"archived"` se usan en seeds/fixtures/código, confirmado por `grep -rn "status:" app/ db/`): `status_label`/`status_badge` devuelven el string crudo sin badge de color reconocible (`bg-light text-dark`), no rompen la vista.
- El filtro "Estado" sigue funcionando con cualquier valor que exista en `Project.distinct.pluck(:status)` (código del controlador sin cambios) — el helper solo cambia qué texto se muestra, nunca qué valor se envía en el `<option value="...">`.
