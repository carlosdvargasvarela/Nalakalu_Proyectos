# Exigir fechas de etapas por Tipo de Proyecto

## Contexto

Nalakalú permite guardar etapas de proyecto (`project_stages`) sin `start_date`/
`end_date` — hoy no hay validación ni restricción. Hay dos vistas Gantt:

- **Gantt de un proyecto individual** (`app/views/projects/show.html.erb`, líneas
  27-45): una barra por etapa. Etapas sin fecha reciben un placeholder
  (`created_at` del proyecto + 7 días) y se muestran igual.
- **Gantt del listado por tipo de proyecto** (`app/views/projects/_project_type_section.html.erb`,
  líneas 87-118, sección "Cronograma"): una barra por proyecto, usando
  `Project#gantt_window` (rango agregado de todas sus etapas) o, si hay un filtro
  de etapa activo (`section[:stage_name]`), una barra por proyecto usando esa etapa
  puntual con el mismo placeholder de 7 días si le falta fecha.

`Project#start_date`/`#end_date` (app/models/project.rb:27-33) ya ignoran etapas sin
fecha vía `.compact` al calcular el rango agregado — no hace falta tocar eso.

## Objetivo

Permitir marcar un Tipo de Proyecto como "exige fechas de etapa". Para los
proyectos de esos tipos, las etapas sin fecha dejan de aparecer en el Gantt
(sin placeholder), y se agrega una sección visible que señala qué proyectos
tienen etapas pendientes de fecha. Para tipos de proyecto sin el flag activo,
el comportamiento actual no cambia.

No es una validación dura: se puede seguir guardando una etapa sin fecha. El
efecto es solo de visualización (qué aparece en el Gantt) y de aviso (el panel
de pendientes y el contador de navbar).

## Modelo de datos

Migración: agregar `require_stage_dates:boolean, default: false, null: false` a
`project_types`.

`ProjectType` (app/models/project_type.rb): sin cambios de asociación, solo el
nuevo atributo.

Admin: `app/controllers/admin/project_types_controller.rb` permite
`:require_stage_dates` en `project_type_params`. `app/views/admin/project_types/_form.html.erb`
agrega un checkbox "Exigir fechas en las etapas", mismo patrón visual que el
checkbox `default_in_filter` de `app/views/admin/stage_templates/_form.html.erb`.

## Comportamiento del Gantt

**Gantt de proyecto individual** (`projects/show.html.erb`): al construir
`gantt_tasks`, si `@project.project_type.require_stage_dates?` es verdadero, se
omiten (no se agregan al array) las etapas donde `start_date.blank? ||
end_date.blank?` — sin aplicar el placeholder de 7 días para esas etapas. Las
etapas con fecha se muestran normalmente. La tabla de etapas debajo del Gantt
(`_stage_table.html.erb`) no cambia — la etapa sigue editable ahí aunque no
aparezca en el gráfico.

**Gantt de listado por tipo** (`_project_type_section.html.erb`): en el caso
general (usa `gantt_window`) se omite el proyecto por completo cuando
`project_type.require_stage_dates?` es verdadero y TODAS sus etapas están sin
fecha — de lo contrario `gantt_window` cae al placeholder de una semana
(`created_at..created_at+7.days`) y el proyecto aparecería como barra en el
Cronograma a la vez que en el panel "Pendientes de fecha", contradiciendo esa
sección. Si al menos una etapa tiene fecha, `gantt_window` sigue usándose sin
cambios. Cuando hay un filtro de etapa activo (`section[:stage_name].present?`) y
`project_type.require_stage_dates?` es verdadero, se omite el proyecto de
`gantt_tasks` si la etapa filtrada no tiene `start_date`/`end_date` (en vez de
aplicarle el placeholder de 7 días).

Tipos de proyecto con el flag apagado: cero cambios de comportamiento en ambos
Gantt.

## Panel "Proyectos pendientes de fecha"

En `_project_type_section.html.erb`, antes de la tarjeta "Cronograma": una
nueva tarjeta que solo se renderiza si `project_type.require_stage_dates?` es
verdadero y hay al menos un proyecto pendiente. Lista, entre los proyectos ya
filtrados por los filtros activos de la sección (`section[:projects_list]`),
los que tienen alguna etapa con `start_date.blank? || end_date.blank?`: nombre
del proyecto (link a `project_path`) y los nombres de las etapas que le faltan
completar. Sin proyectos pendientes → la tarjeta no se muestra.

Método nuevo en `Project`: `stages_missing_dates` → etapas donde
`start_date.blank? || end_date.blank?`. Se usa tanto para filtrar `gantt_tasks`
como para construir este panel.

## Badge en la navbar

Junto al link "Proyectos" en `app/views/layouts/_navbar.html.erb`: un badge con
el número total de proyectos pendientes de fecha, visible en toda la app,
respetando `Project.visible_to(current_user)` (mismo scope que ya usa el resto
de la app para permisos). Solo se muestra si el número es mayor a 0. Se calcula
con una query SQL directa (no cargar proyectos en memoria):

```ruby
Project.visible_to(current_user)
  .joins(:project_type, :project_stages)
  .where(project_types: { require_stage_dates: true })
  .where("project_stages.start_date IS NULL OR project_stages.end_date IS NULL")
  .distinct
  .count
```

Vive como método `pending_stage_dates_count(user)` en `ApplicationHelper`,
llamado directamente desde `_navbar.html.erb` con `current_user`.

## Testing

- Modelo: test de `ProjectType` para el nuevo atributo (default false) y de
  `Project#stages_missing_dates`.
- Controlador/vista: test de que el Gantt de un proyecto omite etapas sin
  fecha cuando el tipo lo exige, y las muestra cuando no. Test de que el panel
  de pendientes aparece/no aparece según corresponda. Test de que el badge de
  navbar cuenta correctamente y respeta `visible_to`.
- Sin tests de sistema nuevos (la app no los usa hoy) — verificación visual
  manual en navegador antes de dar el trabajo por terminado, como en el
  refresh de UI anterior.
