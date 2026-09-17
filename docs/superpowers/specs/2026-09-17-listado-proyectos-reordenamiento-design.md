# Reordenamiento y limpieza del listado de proyectos

**Fecha:** 2026-09-17
**Alcance:** `app/views/projects/_project_type_section.html.erb`, `app/views/projects/index.html.erb`, `app/views/layouts/_navbar.html.erb`
**Fuera de alcance:** vistas de detalle (`show`/`tracker`) y formularios (`new`/`edit`/`select_type`) — quedan para sub-proyectos posteriores.

## Motivación

El listado de proyectos (`/projects/tipo/:slug`) se siente sobrecargado y con una
distribución poco lógica. Verificado con Playwright contra datos reales de
desarrollo (37 proyectos de tipo Instalaciones): el orden actual de la página es

1. Filtros (7 campos en una fila)
2. Stats (Total / Vencidos / Finalizados)
3. **Pendientes de fecha** — lista sin paginar con ~24 filas repetitivas
4. **Cronograma** — Gantt que ocupa ancho completo, a menudo casi vacío
5. **Listado** — la tabla de proyectos, el contenido que el usuario busca primero

El contenido principal (el listado) queda al final, detrás de dos bloques de
información secundaria que consumen la mayor parte del alto de la página.

## Diseño

### 1. Orden de secciones

Nuevo orden en `_project_type_section.html.erb`:

1. Filtros
2. Stats
3. **Listado** (sube al segundo lugar después de las stats)
4. Panel plegable "Pendientes de fecha (N)"
5. Panel plegable "Cronograma"

El HTML/lógica de cada bloque no cambia de fondo, solo su posición en el
template y el wrapper plegable de los dos últimos.

### 2. Panel "Pendientes de fecha" colapsable

- El `card-header` pasa a ser un botón que expande/colapsa (Bootstrap
  `collapse`, ya disponible en el proyecto — sin dependencias nuevas).
- Título: `"Pendientes de fecha (#{pending_projects.size})"`. Colapsado por
  defecto.
- Si `pending_projects` está vacío, la sección no se renderiza en absoluto
  (comportamiento actual, se mantiene).
- La lista interna no cambia (misma lógica de `missing`/`needs_start`/botón
  "Calcular"); solo se pagina igual que el Listado si supera un umbral, para no
  reintroducir una lista larga sin cortar. Umbral: 10 filas por página,
  reutilizando el mismo patrón de paginación Kaminari-like que ya usa
  `page_projects`/`section[:total_pages]` (paginación manual con `.slice`,
  sin gema nueva — ya es como está implementado el Listado).

### 3. Panel "Cronograma" colapsable

- Mismo patrón: `card-header` como botón de colapso, colapsado por defecto.
- Contenido interno (Gantt, botones de vista Día/Semana/Mes, botón invertir
  orden, leyenda) no cambia.
- Importante: Frappe Gantt no calcula bien su ancho si se inicializa dentro de
  un contenedor `display: none`. Se inicializa el gráfico (Stimulus
  `gantt-project-list` controller) solo cuando el panel se expande por primera
  vez, escuchando el evento `shown.bs.collapse` de Bootstrap, en vez de en
  `connect()` incondicional.

### 4. Filtros: básicos vs. avanzados

- Fila visible siempre: **Estado** y **Buscar**.
- Detrás de un botón "Más filtros" (toggle, mismo patrón de collapse):
  Tipo de responsable, Responsable, Desde, Hasta, Etapa.
- Si alguno de los filtros avanzados tiene un valor activo (viene en
  `section_params`), el panel avanzado empieza expandido para que el usuario
  vea qué filtro está aplicado — evita el caso confuso de "tengo un filtro
  puesto pero no lo veo".

### 5. Navbar (`_navbar.html.erb`)

- Los 4 enlaces de admin (Administración, Responsables, Tipos de asociación,
  Usuarios) se agrupan en un dropdown Bootstrap "Administración" (mismo
  patrón `dropdown`/`dropdown-menu` ya usado en el resto de la app vía
  Bootstrap, sin JS adicional).
- El badge rojo de conteo de pendientes junto a "Proyectos": se le agrega
  `title`/`aria-label` = `"#{pending_count} proyecto(s) con fecha pendiente"`,
  y se envuelve en un enlace que apunta a `/projects` con un query param
  (`#pendientes-de-fecha` anchor) para que al llegar al listado el panel de
  pendientes se abra automáticamente. Esto reutiliza el mismo dato
  (`pending_stage_dates_count`) que ya calcula el helper existente —
  no se agrega una nueva fuente de verdad.

## Fuera de alcance / explícitamente descartado

- **Inconsistencia de badges de estado**: se investigó una aparente mezcla de
  badges con color vs. texto plano en la columna Estado. Se confirmó que era
  un artefacto de datos de prueba con valores de `status` inválidos
  (`"activo"`, `"pausado"`, `"finalizado"`) que no existen en el dominio real
  (`STATUS_LABELS`/`STATUS_BADGE_CLASSES` solo definen `"active"` y
  `"archived"`, `app/helpers/application_helper.rb:17-18`). No hay bug real
  aquí; no se incluye ningún cambio de código para esto.
- Mover "Pendientes de fecha"/"Cronograma" a una pestaña separada o a otra
  página: descartado por el usuario a favor de paneles plegables en la misma
  página.
- Rediseño visual del navbar más allá de agrupar el dropdown de admin (paleta,
  tipografía, etc.): no solicitado, fuera de alcance.

## Testing

- Test de sistema/request existente para `projects#index` (ya cubre filtros y
  paginación) se actualiza para verificar: el listado aparece antes que
  "Pendientes de fecha" en el HTML renderizado (orden de nodos), y que ambos
  paneles nuevos tienen la clase `collapse` sin `show` por defecto.
- Test nuevo y pequeño para el dropdown de admin en el navbar: los 4 enlaces
  siguen presentes (mismo `href`), ahora dentro de un `.dropdown-menu`.
- No se agregan tests de JS/Stimulus nuevos (fuera del patrón existente en el
  proyecto, que no tiene suite de JS).
