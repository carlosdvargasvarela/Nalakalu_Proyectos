# Refresh visual UI/UX — Nalakalú

## Contexto

Nalakalú es una app Rails 7 (Turbo + Stimulus) de gestión de proyectos, con vistas
en `app/views` (proyectos, admin, gantt) y estilos en CSS plano
(`app/assets/stylesheets/application.css`, `gantt.css`). No usa ningún framework CSS
(Tailwind/Bootstrap).

## Objetivo

Modernizar la apariencia visual de la app sin cambiar de framework ni reestructurar
vistas: nueva paleta, tipografía, componentes más pulidos (tarjetas, tablas, botones,
badges, formularios) y soporte de modo oscuro con toggle manual.

Fuera de alcance: rediseño de navegación/layout, restyling del Gantt (`gantt.css`)
más allá de las variables de color compartidas, migración a un framework CSS.

## Estilo

Flat design con un toque de profundidad: colores sólidos, bordes limpios, sin
gradientes, pero con sombra sutil en tarjetas (`box-shadow` ligero) para dar
jerarquía visual. Bajo en complejidad, compatible con CSS plano.

## Paleta de colores (custom properties)

| Token | Light | Dark |
|---|---|---|
| `--color-primary` | `#2563EB` | `#3B82F6` |
| `--color-bg` | `#F8FAFC` | `#0F172A` |
| `--color-fg` | `#1E293B` | `#F1F5F9` |
| `--color-card` | `#FFFFFF` | `#1E293B` |
| `--color-muted` | `#E9EFF8` | `#334155` |
| `--color-border` | `#E2E8F0` | `#334155` |
| `--color-destructive` | `#DC2626` | `#EF4444` |
| `--color-success` | `#059669` | `#10B981` |

Azul como color de marca (botones primarios, links, focus ring). Grises neutros
para fondo/texto/bordes. Verde/rojo reservados para estados (badges, alertas).
Contraste mínimo 4.5:1 en ambos modos.

## Tipografía

Una sola familia: **Inter** (pesos 400/500/600/700), para headings y body. Un solo
`@import` de Google Fonts. Tamaño base 16px, `line-height: 1.5`.

## Modo oscuro

Toggle manual en la navbar:
- Nuevo Stimulus controller `theme_controller.js` (mismo patrón que los controllers
  existentes en `app/javascript/controllers/`).
- Al cargar, usa `prefers-color-scheme` como valor inicial si no hay preferencia
  guardada.
- El toggle setea `data-theme="light"|"dark"` en `<html>` y persiste la elección en
  `localStorage`.
- Todas las variables de color se redefinen bajo `:root` (light, default) y
  `[data-theme="dark"]` / `@media (prefers-color-scheme: dark)` (dark).

## Componentes a restilizar

Todo dentro de `app/assets/stylesheets/application.css`, reutilizando las clases y
estructura ERB existentes (sin tocar `gantt.css` salvo exponer las custom properties
de color para que el Gantt las herede):

- Navbar (`_navbar.html.erb`)
- Tarjetas (sombra sutil, borde, radio de esquina)
- Tablas (filas de listados en proyectos/admin)
- Botones (primario, secundario, destructivo)
- Badges de estado (éxito, alerta, error)
- Formularios (inputs, selects, focus rings)

## Testing

Cambio puramente visual/CSS + un Stimulus controller pequeño (toggle + localStorage).
No requiere tests de sistema nuevos; se verifica manualmente en navegador (light/dark,
navbar, listados, formularios) antes de dar el trabajo por terminado.
