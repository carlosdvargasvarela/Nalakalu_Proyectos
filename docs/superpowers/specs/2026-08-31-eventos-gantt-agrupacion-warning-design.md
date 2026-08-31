# Agrupación de marcadores y aviso de fecha fuera de etapa

**Fecha:** 2026-08-31
**Estado:** Aprobado, pendiente de plan de implementación

## Problema

Sobre la base ya implementada de eventos en el Gantt (spec
`2026-08-31-eventos-proyecto-gantt-design.md`), surgen dos ajustes:

1. Cuando varios eventos de la misma etapa caen en fechas cercanas, sus
   marcadores se solapan visualmente en el Gantt y se vuelven ilegibles.
2. Un evento puede asociarse a una etapa cuya fecha de inicio/fin no
   incluye la fecha del evento, y hoy no hay ninguna señal de eso al
   cargarlo — la app lo permite igual (correcto), pero sin avisar.

## Alcance

Solo toca el Gantt de detalle de proyecto (`projects/show.html.erb` /
`gantt_stage_editor_controller.js`) y el formulario compartido de eventos
(`_event_fields.html.erb`). No hay cambios de modelo ni de validaciones de
backend — el aviso de fecha es puramente informativo en el cliente.

## 1. Agrupación de marcadores por proximidad en píxeles

En `drawEventMarkers()`, antes de dibujar los marcadores de una etapa:

- Calcular la posición X de cada evento de esa etapa (ya se calcula hoy).
- Ordenar por X y agrupar en clusters greedy: un evento se une al cluster
  anterior si su X está a menos de 16px de la X del último evento agregado
  a ese cluster (16px ≈ diámetro actual del rombo, `size * 2 + 2`).
- Cluster de 1 evento: se dibuja igual que hoy — rombo del color de su
  `event_type`, tooltip nativo `"Título — fecha"`, click abre
  `#edit-event-modal-<id>`.
- Cluster de 2+ eventos: un rombo más grande (radio ~10 en vez de 7),
  relleno gris neutro (`#495057`) ya que no puede representar más de un
  color a la vez, con un texto centrado mostrando la cantidad. El tooltip
  nativo (`<title>`) lista `"Título — fecha"` de cada evento del grupo,
  uno por línea. Al hacer click, en vez de abrir un modal directamente, se
  despliega una lista flotante simple (un `<div>` posicionado junto al
  marcador, sin dependencias nuevas) con un ítem por evento; cada ítem abre
  el modal de edición de ese evento (`#edit-event-modal-<id>`) y cierra la
  lista al elegir o al hacer click afuera.

Esta agrupación aplica igual en la fila sintética "Eventos del proyecto"
(los eventos sin etapa), ya que `drawEventMarkers` trata esa fila como una
más.

## 2. Aviso de fecha fuera del rango de la etapa

En `_event_fields.html.erb`, un nuevo controlador Stimulus (`event-date-range-warning`)
recibe como dato las fechas de cada etapa del proyecto
(`{stage_id: [start_date, end_date]}`, `null` si a la etapa le falta alguna
fecha). Cuando cambia el select de etapa o el campo de fecha:

- Si la etapa elegida es "Todo el proyecto" (sin etapa) → sin aviso.
- Si a la etapa le falta alguna fecha → sin aviso (no hay rango contra qué
  comparar).
- Si la fecha del evento cae fuera de `[start_date, end_date]` de la etapa
  elegida → se muestra un texto de advertencia (`text-warning`, ícono
  `bi-exclamation-triangle`) debajo del campo de fecha: *"La fecha está
  fuera del rango de la etapa (dd/mm — dd/mm)."*
- En cualquier otro caso → el aviso se oculta.

No bloquea el envío del formulario ni agrega validación en `Event`. Aplica
tanto al modal de alta como al de edición (ambos comparten
`_event_fields.html.erb`).

## Fuera de alcance

- Persistir o mostrar el aviso en la tabla de eventos o en el servidor.
- Cambiar el criterio de agrupación por zoom real de frappe-gantt (se usa
  un umbral fijo de 16px, independiente del modo Día/Semana/Mes — la
  posición X ya refleja el ancho de columna actual, así que el umbral fijo
  sigue siendo válido en cualquier modo).
