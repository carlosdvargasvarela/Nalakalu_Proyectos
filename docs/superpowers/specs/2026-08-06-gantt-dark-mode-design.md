# Modo oscuro para el Gantt

## Contexto

Frappe Gantt 1.2.2 (la librería que usan ambos gráficos de la app —
`gantt-stage-editor` en `projects/show.html.erb` y `gantt-project-list` en
`_project_type_section.html.erb`) trae soporte de modo oscuro nativo,
completo, ya construido: su CSS define toda la paleta (grilla, encabezados,
popups, etiquetas, etc.) como custom properties bajo `:root` y las
redefine bajo el selector `html[data-theme="dark"]`.

Nuestra app togglea un atributo distinto — `data-bs-theme` (el que usa
Bootstrap) — en `theme_controller.js` (`app/javascript/controllers/theme_controller.js`)
y en el script anti-flash de `app/views/layouts/application.html.erb:12`.
Frappe Gantt nunca ve ese atributo, así que su Gantt queda con la paleta
clara fija sin importar el tema de la app.

El único CSS propio que la app agrega sobre frappe-gantt vive en
`app/assets/stylesheets/gantt.css` — pisa el color de relleno de la barra
(`--bar-fill`, por stage/responsable) y fuerza el overlay de la barra de
progreso a `rgba(0, 0, 0, 0.25)` fijo (negro semi-transparente), para que
se vea sobre colores de barra arbitrarios. Ese negro fijo pierde contraste
sobre barras ya oscuras en dark mode.

## Objetivo

Que ambos Gantt usen el tema oscuro de la app automáticamente, usando la
paleta nativa de frappe-gantt (sin inventar colores propios para la
grilla/encabezados/popups), y que el overlay de progreso siga siendo
visible en dark mode.

## Sincronizar el atributo de tema

`theme_controller.js` setea `data-theme` en `<html>` junto con
`data-bs-theme`, en el mismo método `apply(theme)` — un atributo más, mismo
valor (`"light"`/`"dark"`), sin lógica nueva.

El script anti-flash inline en `application.html.erb:12` (que evita el
parpadeo de tema claro en cada carga completa de página) hace lo mismo:
setea ambos atributos con el mismo valor calculado, para que el Gantt no
parpadee en claro al cargar una página en modo oscuro.

## Overlay de progreso visible en dark mode

En `gantt.css`, agregar una regla para `[data-bs-theme="dark"] .bar-progress`
con un overlay claro (blanco semi-transparente) en vez del negro fijo que
usa el modo claro — mismo espíritu que el resto del refresh visual: cada
color que dependía del tema recibe su contraparte oscura explícita.

## Fuera de alcance

No se toca el color de las barras en sí (`--bar-fill`, por stage/responsable
— ese color lo define el usuario en el admin, es independiente del tema) ni
ningún otro estilo de `gantt.css`. No se define una paleta oscura propia
para el Gantt — se usa la que ya trae frappe-gantt.

## Testing

- Test de controlador: confirmar que `theme_controller.js` y el script
  inline de `application.html.erb` setean `data-theme` además de
  `data-bs-theme` (con el mismo valor, `assert_match` sobre el código
  fuente — mismo patrón que ya usan los tests existentes de Gantt/JS en
  esta app).
- Test de que `gantt.css` contiene la regla de overlay de progreso oscuro.
- Sin test de sistema (la app no los usa hoy) — verificación visual manual
  en navegador, en ambos Gantt y ambos temas, antes de dar el trabajo por
  terminado.
