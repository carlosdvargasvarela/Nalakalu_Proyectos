# Eliminar N+1 en el detalle de proyecto (`/projects/:id`)

## Contexto

Los logs de producción (Heroku, `nalakalu-proyectos`) muestran cargas de
`ProjectsController#show` con 53 a 97 queries y hasta ~7 segundos de tiempo
en base de datos (`ActiveRecord: 6799.0ms (53 queries, 24 cached)` para
`/projects/107`, patrones similares para `/projects/16`). El plan de
Postgres en Heroku es `essential-0` (el más económico), donde cada
round-trip de red pesa más que en un plan mayor — así que reducir la
*cantidad* de queries importa más de lo habitual acá.

Investigación (leyendo `app/controllers/projects_controller.rb:37-46` y
`app/views/projects/show.html.erb`) encontró dos causas concretas, ambas
en la misma acción:

1. **`@project_change_versions` no precarga `item`.** La sección
   "Historial de cambios" (show.html.erb, el `each` sobre
   `@project_change_versions`) llama `version.item.name` para versiones de
   tipo `ProjectStage` — `PaperTrail::Version#item` es un
   `belongs_to :item, polymorphic: true, optional: true`
   (paper_trail-17.0.0, `lib/paper_trail/version_concern.rb:25`). Sin
   `.includes(:item)`, cada acceso a `.item` en el loop dispara su propia
   query — hasta 50 queries extra (el `.limit(50)` de la consulta), una
   por versión. Esto es la causa dominante de los conteos vistos en
   producción.

2. **`projects_by_other_type` carga TODOS los proyectos de la app**
   (`show.html.erb:144`), sin filtrar por tipo, solo para armar el
   `<select>` dependiente de "Proyecto" en el formulario de Asociaciones.
   No es N+1 (es una sola query), pero no escala: con más proyectos en la
   base, esta única query crece sin límite aunque casi ningún proyecto sea
   relevante para el formulario.

## Cambio

### 1. Precargar `item` en `@project_change_versions`

`app/controllers/projects_controller.rb:37-46`, agregar `.includes(:item)`
a la query:

```ruby
def show
  @project_change_versions = PaperTrail::Version
    .where(item_type: "Project", item_id: @project.id)
    .or(PaperTrail::Version.where(item_type: "ProjectStage", item_id: @project.project_stage_ids))
    .order(created_at: :desc)
    .limit(50)
    .includes(:item)

  whodunnit_ids = @project_change_versions.map(&:whodunnit).compact
  @version_authors = User.where(id: whodunnit_ids).index_by { |u| u.id.to_s }
end
```

Con versiones mezclando `item_type` "Project" y "ProjectStage",
`.includes(:item)` agrupa por tipo y dispara como máximo una query por
cada tipo presente en el resultado (1 o 2 queries totales), en vez de una
por registro.

### 2. Acotar `projects_by_other_type` a los tipos relevantes

`app/views/projects/show.html.erb:139-145`. Los tipos "relevantes" son
exactamente los `other_type_id` que ya se calculan al armar
`association_options` — se reutiliza ese cálculo (no agrega una vuelta
extra sobre `applicable_associations`, que ya se recorre una vez):

```erb
<%
  applicable_associations = ProjectTypeAssociation.where(from_project_type: @project.project_type).or(ProjectTypeAssociation.where(to_project_type: @project.project_type))
  association_options = applicable_associations.map do |a|
    other_type_id = a.from_project_type_id == @project.project_type_id ? a.to_project_type_id : a.from_project_type_id
    [a.label, a.id, { data: { key: other_type_id } }]
  end
  relevant_type_ids = association_options.map { |_, _, opts| opts[:data][:key] }.uniq
  projects_by_other_type = Project.where.not(id: @project.id).where(project_type_id: relevant_type_ids).order(:name).group_by(&:project_type_id)
    .transform_values { |projects| projects.map { |p| [p.id, p.name] } }
%>
```

Si `relevant_type_ids` es un array vacío (el proyecto no tiene ningún tipo
de asociación configurado), `Project.where(project_type_id: [])` devuelve
un relation vacío sin error — comportamiento estándar de ActiveRecord, no
hace falta un guard adicional.

## Fuera de alcance

- El loop `ProjectTypeAssociation.where(to_project_type: ...).each` que
  llama `current_user.can_create_associated_project?(association, @project)`
  por cada asociación (`show.html.erb`, más abajo en el mismo archivo)
  dispara queries adicionales vía `can_view_project?`, pero solo para
  usuarios con rol "responsable" y solo cuando
  `association.responsables_can_create?` es true — de alcance chico dado
  el volumen actual de `ProjectTypeAssociation` por tipo. No se toca hoy.
- La causa de infraestructura (conexión lenta a Postgres `essential-0` en
  el login, vista en los logs) es una decisión de costo/plan del usuario,
  no un cambio de código — no forma parte de este spec.
- No se agrega paginación ni límite nuevo al historial de cambios (ya
  tiene `.limit(50)`) ni a las asociaciones/responsables — solo se arregla
  cómo se cargan los datos ya limitados.

## Testing

- Test de queries: crear un proyecto, generar varias versiones de
  PaperTrail actualizando sus `ProjectStage` (dispara `has_paper_trail`
  automáticamente), y confirmar con un conteo de queries (no
  `assert_queries_count` sin argumento — ver la lección aprendida en el
  plan de la columna de responsables, ese método sin un count esperado no
  sirve para comparar) que cargar `/projects/:id` con 5 versiones de
  historial no dispara más queries que con 2 — es decir, que agregar
  historial no escala la cantidad de queries.
- Test funcional: el historial de cambios sigue mostrando correctamente
  el nombre de la etapa (`(Etapa: <nombre>)`) para versiones de tipo
  `ProjectStage`, confirmando que `.includes(:item)` no rompe el acceso a
  `version.item.name` que ya usaba la vista.
- Test de `projects_by_other_type`: con proyectos de un tipo NO
  relacionado por ninguna `ProjectTypeAssociation` con el tipo del
  proyecto actual, ese tipo no aparece en el JSON
  `data-dependent-select-options-value` del formulario de asociaciones —
  confirma que el filtro por `relevant_type_ids` efectivamente excluye
  proyectos irrelevantes (antes de este cambio, aparecían todos).
- Correr la suite completa para confirmar que no se rompe nada del resto
  de la página (Responsables, Bitácora, Cronograma).
