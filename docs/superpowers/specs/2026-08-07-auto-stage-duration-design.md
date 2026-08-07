# Duración automática de etapas por regla numérica

## Contexto

Hoy las etapas de un proyecto (`project_stages`) se crean vacías (sin fechas)
al crear el proyecto, vía `Project#build_stages_from_template`
(app/models/project.rb:65-69), que simplemente recorre
`project_type.stage_templates` y crea una `ProjectStage` por cada una, sin
fechas. El usuario completa las fechas a mano después, en la tabla de
etapas de cada proyecto.

`FieldDefinition` (app/models/field_definition.rb) define los campos custom
de un tipo de proyecto — entre ellos los numéricos (`data_type` en
`number`/`currency`/`percent`). Sus valores viven en `projects.custom_fields`
(jsonb). El formulario de "Nuevo proyecto" (`app/views/projects/_form.html.erb`,
compartido con "Editar") ya renderiza un input por cada `field_definition`
del tipo.

El panel "Pendientes de fecha" (`app/views/projects/_project_type_section.html.erb`,
líneas ~130-152, de la feature `require_stage_dates`) ya lista proyectos con
alguna etapa sin fecha, para tipos de proyecto que "exigen fechas". Esa
feature es independiente de esta — un tipo de proyecto puede tener una,
otra, ambas, o ninguna activa.

La importación por Excel (`app/controllers/imports_controller.rb`, método
`commit_rows`, línea 44-59) crea proyectos vía `Project.new(...).save`, sin
pasar por el formulario — dispara el mismo callback `build_stages_from_template`,
así que los proyectos importados nunca tienen fecha de inicio a menos que
se la asignen después.

## Objetivo

Permitir que un Tipo de Proyecto configure una duración automática de
etapas: al crear un proyecto (a mano, con fecha de inicio provista), se
calculan las fechas de cada etapa en cadena, según cuál "perfil de
duración" matchee el valor de un campo numérico del proyecto. Es 100%
configurable por tipo de proyecto — apagado por defecto, no afecta a los
tipos que no lo activen.

## Modelo de datos

**`ProjectType`** gana dos columnas:
- `auto_stage_duration_enabled:boolean, default: false, null: false`
- `duration_reference_field_definition_id` (FK opcional a `field_definitions`,
  `null: true` — el campo numérico usado como referencia para las reglas).

**Nuevo modelo `DurationProfile`** (una regla = un perfil completo de
duraciones para todas las etapas):
- `project_type_id` (FK, `null: false`)
- `operator:string` — uno de `greater_than`, `less_than`, `between`, `equal_to`
- `min_value:decimal` (nullable — usado por `greater_than`, `between`, `equal_to`)
- `max_value:decimal` (nullable — usado por `less_than`, `between`)
- `position:integer, default: 0` — orden de prioridad; si el valor matchea
  varios perfiles, gana el de menor `position` (mismo patrón de
  arrastrar-para-reordenar que ya usan `stage_templates`/`field_definitions`)
- `durations:jsonb, default: {}, null: false` — `{ "<stage_template_id>": dias_integer, ... }`,
  mismo estilo de columna jsonb que `shared_field_mappings` en
  `ProjectTypeAssociation`.

Coincidencia de un valor `V` contra un perfil:
- `greater_than`: `V > min_value`
- `less_than`: `V < max_value`
- `between`: `min_value <= V <= max_value`
- `equal_to`: `V == min_value` (se reutiliza `min_value` como el valor exacto,
  no se agrega una columna `value` aparte)

## Cálculo de fechas al crear un proyecto

Nuevo método en `Project`, invocado desde `build_stages_from_template`
cuando `project_type.auto_stage_duration_enabled?` es verdadero y se proveyó
una fecha de inicio (ver "Formulario de creación" abajo):

1. Tomar el valor del campo de referencia:
   `custom_fields[project_type.duration_reference_field_definition.key]`,
   convertido a `Float`.
2. Buscar el primer `DurationProfile` (ordenado por `position`) cuya regla
   cubra ese valor.
3. Si no hay perfil que matchee, o no se proveyó fecha de inicio, o el tipo
   no tiene el cálculo activo, o el tipo no tiene `duration_reference_field_definition`
   configurado (o su valor está vacío en `custom_fields`): comportamiento
   actual, sin cambios — las etapas se crean sin fecha.
4. Si hay perfil: recorrer `stage_templates` en orden; para cada una, si el
   perfil tiene una entrada en `durations` para ese `stage_template_id`,
   la etapa arranca en la fecha "cursor" (que empieza en la fecha de inicio
   provista) y dura esos días corridos — `end_date = start_date + (dias - 1)`.
   El cursor de la siguiente etapa es `end_date + 1 día`. Si el perfil no
   tiene entrada de duración para esa etapa puntual, esa etapa se crea sin
   fecha y el cursor no avanza para ella (las etapas siguientes siguen
   encadenándose desde el último cursor válido).

## Formulario de creación de proyecto

`app/views/projects/_form.html.erb` (usado solo para creación en este
contexto — cuando `!project.persisted?`): si
`project_type.auto_stage_duration_enabled?`, se agrega un campo obligatorio
"Fecha de inicio" (no es un atributo de `Project`, es un parámetro de
formulario aparte que `ProjectsController#create` lee y pasa al cálculo).
El formulario de edición no lo muestra — las etapas ya existen para un
proyecto guardado, no tiene sentido "recrear" la cadena ahí.

Para tipos sin el cálculo activo, el formulario no cambia.

## Importación por Excel

Sin cambios en `imports_controller.rb` — como no pasa por el formulario, un
proyecto importado nunca trae fecha de inicio, así que cae directo en el
caso "sin fecha" del cálculo (etapas creadas sin fecha, igual que hoy).

## Panel "Pendientes de fecha" ampliado

En `_project_type_section.html.erb`, el panel existente (hoy solo visible
para tipos con `require_stage_dates?`) se amplía: también se muestra
cuando `project_type.auto_stage_duration_enabled?` es verdadero. La lista
de proyectos pendientes incluye, además de los que ya calificaban antes,
los proyectos de tipos con cálculo automático cuya primera etapa
(la primera de `project_type.stage_templates` en orden) no tiene fecha.

Para esos proyectos, la fila del panel muestra un input de fecha + botón
"Calcular" en vez de (o junto a) la lista de etapas faltantes. Al enviarlo
(nuevo endpoint, ej. `PATCH /projects/:id/apply_auto_duration`), se corre
el mismo cálculo de la sección anterior usando esa fecha como inicio,
actualizando las etapas existentes del proyecto (que ya están creadas sin
fecha) en vez de crearlas de nuevo.

## Admin: configurar el cálculo

En `app/views/admin/project_types/show.html.erb`, nueva tarjeta "Cálculo
automático de duración" (mismo patrón visual que las tarjetas de Campos/
Subprocesos ya existentes):
- Checkbox para activar/desactivar (`auto_stage_duration_enabled`).
- Selector del campo de referencia — solo lista `field_definitions` con
  `data_type` en `number`/`currency`/`percent`.
- Tabla de perfiles de duración: una fila por `DurationProfile`, arrastrable
  para reordenar (prioridad, mismo patrón que Subprocesos), con la
  condición (operador + valor(es)) y un input numérico de días por cada
  `stage_template` del tipo. Nuevo/Editar/Eliminar por perfil, mismo patrón
  CRUD que `admin/stage_templates`.

## Fuera de alcance

- No se recalculan fechas si el valor del campo de referencia cambia
  después de creado el proyecto — el cálculo corre una sola vez, al crear
  (o, para importados, al completar la fecha desde el panel de pendientes).
- No se valida que los rangos de los perfiles no se superpongan — la
  prioridad por `position` resuelve cualquier ambigüedad.
- No se agregan tests de sistema (la app no los usa) — verificación manual
  en navegador antes de dar el trabajo por terminado.

## Testing

- Modelo: `DurationProfile` (validaciones de operator/valores según el
  operador), `Project` (cálculo de fechas con distintos perfiles/valores,
  caso sin perfil que matchee, caso stage_template sin entrada de duración).
- Controlador: formulario de creación muestra/oculta el campo de fecha
  según el flag; creación de proyecto calcula fechas correctamente;
  proyecto importado (sin fecha) sigue creándose sin fechas; el panel de
  pendientes lista los proyectos correctos y el endpoint de completar
  fecha calcula y persiste las fechas.
- Admin: CRUD de `DurationProfile`, selector de campo de referencia
  filtrado a tipos numéricos, checkbox de activación.
