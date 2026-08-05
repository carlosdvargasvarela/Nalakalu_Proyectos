# Refresh visual UI/UX — Nalakalú

## Contexto

Nalakalú es una app Rails 7 (Turbo + Stimulus) de gestión de proyectos, con vistas
en `app/views` (proyectos, admin, gantt). **Usa Bootstrap 5.3.3 vía CDN** (más
Bootstrap Icons y tom-select con tema Bootstrap), cargado en
`app/views/layouts/application.html.erb`. Los overrides propios viven en
`app/assets/stylesheets/application.css` (hoy solo redefine `--bs-primary` y unos
pocos componentes) y `gantt.css` (colores de barras via JS, no CSS).

Bootstrap 5.3 trae soporte nativo de modo oscuro vía el atributo
`data-bs-theme="dark"`, que redefine automáticamente todas sus custom properties
`--bs-*`. Esto significa que el refresh no necesita reconstruir componentes: alcanza
con redefinir las variables `--bs-*` de Bootstrap (colores, radios) y usarlas también
para dark mode.

## Objetivo

Modernizar la apariencia visual de la app reutilizando Bootstrap (ya integrado):
nueva paleta y tipografía vía variables `--bs-*`, ajustes de componentes Bootstrap
existentes (tarjetas, tablas, botones, badges, formularios) y modo oscuro nativo de
Bootstrap con toggle manual.

Fuera de alcance: rediseño de navegación/layout, restyling del Gantt (`gantt.css`)
más allá de heredar las variables de color de Bootstrap, migración a otro framework
CSS, eliminar Bootstrap.

## Estilo

Flat design con un toque de profundidad: colores sólidos, bordes limpios, sin
gradientes, pero con sombra sutil en tarjetas (`box-shadow` ligero) para dar
jerarquía visual. Bajo en complejidad, compatible con CSS plano.

## Paleta de colores (variables Bootstrap `--bs-*`)

Se redefinen las custom properties que Bootstrap 5.3 ya expone, tanto bajo `:root`
(modo claro) como bajo `[data-bs-theme="dark"]` (modo oscuro, activado por el toggle).
No se inventan tokens nuevos — se reutiliza el sistema de variables de Bootstrap para
que todos sus componentes (`.btn`, `.card`, `.table`, `.badge`, `.form-control`, …)
hereden el cambio automáticamente.

| Variable Bootstrap | Light | Dark |
|---|---|---|
| `--bs-primary` | `#2563EB` | `#3B82F6` |
| `--bs-success` | `#059669` | `#10B981` |
| `--bs-danger` | `#DC2626` | `#EF4444` |
| `--bs-body-bg` | `#F8FAFC` | `#0F172A` |
| `--bs-body-color` | `#1E293B` | `#F1F5F9` |
| `--bs-border-color` | `#E2E8F0` | `#334155` |
| `--bs-tertiary-bg` (usado por `.card-header`, fondos "muted") | `#E9EFF8` | `#334155` |

`--bs-primary-rgb` debe recalcularse junto con `--bs-primary` (Bootstrap lo usa para
`rgba()` en focus rings, `.btn-outline-primary`, etc.). Azul como color de marca
(botones primarios, links, focus ring). Verde/rojo reservados para estados (badges,
alertas). Contraste mínimo 4.5:1 en ambos modos — ambas paletas parten de los pares
`color`/`color-dark` ya validados por accesibilidad en la búsqueda de diseño.

## Tipografía

Una sola familia: **Inter** (pesos 400/500/600/700), para headings y body, vía
`--bs-body-font-family` (Bootstrap ya usa esta variable para todo el texto). Un solo
`@import` de Google Fonts al inicio de `application.css`. Tamaño base 16px (default
de Bootstrap), `line-height: 1.5`.

## Modo oscuro

Se usa el **modo oscuro nativo de Bootstrap 5.3** (`data-bs-theme="dark"`), no un
sistema propio:
- Nuevo Stimulus controller `theme_controller.js` (mismo patrón que los controllers
  existentes en `app/javascript/controllers/`).
- Al cargar, usa `prefers-color-scheme` como valor inicial si no hay preferencia
  guardada en `localStorage`.
- El toggle (botón en la navbar) alterna `data-bs-theme="light"|"dark"` en `<html>`
  y persiste la elección en `localStorage`.
- Las variables `--bs-*` de la tabla anterior se redefinen bajo `:root` (light) y
  `[data-bs-theme="dark"]` (dark) en `application.css`. Bootstrap propaga estas
  variables a todos sus componentes automáticamente — no hay que redefinir cada
  componente por separado.

## Componentes a restilizar

Se ajustan clases Bootstrap existentes en `app/assets/stylesheets/application.css`
(no se reescriben desde cero), reutilizando la estructura ERB existente. `gantt.css`
no se toca salvo por herencia automática de las variables `--bs-*` (los colores de
barra los sigue poniendo JS por dato, no CSS):

- Navbar (`_navbar.html.erb`) — clases `.navbar`, `.navbar-brand`
- Tarjetas (`.card`, `.card-header`) — sombra sutil, borde, radio de esquina
- Tablas (`.table`) — filas de listados en proyectos/admin
- Botones (`.btn-primary`, `.btn-secondary`, `.btn-danger`)
- Badges de estado (`.badge` + variantes `.text-bg-success/-warning/-danger`)
- Formularios (`.form-control`, `.form-select`) — focus rings acordes a `--bs-primary`

## Testing

Cambio puramente visual/CSS + un Stimulus controller pequeño (toggle + localStorage).
No requiere tests de sistema nuevos; se verifica manualmente en navegador (light/dark,
navbar, listados, formularios) antes de dar el trabajo por terminado.
