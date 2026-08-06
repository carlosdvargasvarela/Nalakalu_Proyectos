# Ordenar el Gantt de listado por fecha, con opción de invertir

## Contexto

`app/views/projects/_project_type_section.html.erb` (sección "Cronograma") arma
`gantt_tasks` a partir de `projects_list` (`ProjectsController#build_section`,
`app/controllers/projects_controller.rb:280`), que está ordenado por
`Project.order(:name)`. Ese orden alfabético es el que hoy determina en qué
orden aparecen las barras del Gantt — no tiene relación con las fechas de las
barras.

Cada tarea del array `gantt_tasks` ya trae un campo `start` (string ISO), la
misma fecha que posiciona la barra en el gráfico: `project.gantt_window`
cuando no hay filtro de etapa activo, o la fecha de la etapa filtrada cuando
`section[:stage_name]` está presente.

El Gantt lo renderiza `app/javascript/controllers/gantt_project_list_controller.js`
(Stimulus), que ya tiene un patrón de botones de control (Día/Semana/Mes,
líneas 30-35 de `_project_type_section.html.erb`) que actúan puramente en el
cliente sin recargar la página.

## Objetivo

Las barras del Gantt de listado aparecen ordenadas por fecha ascendente
(las más tempranas primero) por defecto, con un botón para invertir el orden
al instante, sin recargar la página. Alcance: solo el Gantt — la tabla
"Listado" de abajo sigue ordenada por nombre, sin cambios. El orden no
persiste entre cargas de página (siempre arranca ascendente).

## Orden por defecto (server-side)

En `_project_type_section.html.erb`, después de construir `gantt_tasks` (el
`filter_map` existente), ordenar el array resultante por `start` ascendente
antes de pasarlo a `data-gantt-project-list-tasks-value`:

```ruby
gantt_tasks = gantt_tasks.sort_by { |task| task[:start] }
```

Los strings de fecha son ISO 8601 (`YYYY-MM-DD`), así que el orden
lexicográfico coincide con el orden cronológico — no hace falta parsear a
`Date`.

## Toggle de inversión (client-side)

Un botón nuevo (ícono ↑/↓, `bi-sort-down`/`bi-sort-up` de Bootstrap Icons, ya
cargado en la app) en el mismo `btn-group` que Día/Semana/Mes
(`_project_type_section.html.erb`, junto al `id="view-mode-<%= slug %>"`).

En `gantt_project_list_controller.js`:
- Nuevo target `sortButton` y estado `ascending` (empieza `true` en `connect()`).
- Acción `toggleSort()`: invierte `this.tasksValue` (`.slice().reverse()`, sin
  mutar el value original — un segundo click debe volver al orden original,
  no invertir dos veces algo ya invertido en el lugar), llama a
  `this.gantt.refresh(reversed)`, actualiza el ícono del botón, y vuelve a
  llamar `this.applyColors()` (el `refresh()` de Frappe Gantt reconstruye los
  elementos `.bar-wrapper`, así que los colores inline hay que reaplicarlos —
  mismo patrón que ya usa `changeViewMode()`).

No se toca el orden de `projects_list` ni de la tabla "Listado".

## Testing

- Test de controlador (`test/controllers/projects_controller_test.rb`):
  crear proyectos con fechas de etapa en distinto orden que sus nombres,
  pedir el índice, y verificar que `data-gantt-project-list-tasks-value`
  viene ordenado por `start` ascendente — confirma que el orden alfabético
  de antes ya no es el que determina la posición de las tareas.
- El toggle en sí (JS puro, sin round-trip al servidor) se verifica
  manualmente en navegador — no hay test de sistema (Capybara) en esta app
  hoy, y el resto del Gantt (Día/Semana/Mes) tampoco tiene test de
  interacción JS, solo se verifica que el código fuente contiene los
  patrones esperados (`assert_match` sobre el archivo JS), como ya hacen los
  tests existentes de `gantt_project_list_controller.js`.
