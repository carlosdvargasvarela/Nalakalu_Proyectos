# Campos compartidos entre proyectos asociados — Design

## Contexto

Ya existen `ProjectTypeAssociation` (configura qué tipos de proyecto pueden asociarse, bajo qué etiqueta) y `ProjectAssociation` (el vínculo real entre dos `Project`). El flujo "quick-create" permite crear un proyecto nuevo ya vinculado a uno existente (`ProjectsController#new`/`#create` con `project_type_association_id` + `associate_with_project_id`).

Cada `Project` tiene un `custom_fields` (jsonb) cuyas claves están definidas por `FieldDefinition` (scoped a un `ProjectType`: `key`, `label`, `data_type`, `reference_table` si `data_type == "reference"`). Dos `ProjectType` distintos pueden compartir la misma `key` por convención (ej. `"cliente"` en varios tipos), pero nada los relaciona hoy.

**Problema:** si el proyecto A tiene proyectos asociados de otro tipo, es probable que compartan datos (ej. el mismo cliente), y hoy hay que volver a tipearlos a mano en el quick-create.

## Objetivo

Al hacer quick-create de un proyecto asociado, precargar en el formulario los `custom_fields` cuyo valor viene del proyecto origen — pero solo para las keys que un admin marcó explícitamente como "compartidas" para ese par de tipos, no automáticamente.

## Fuera de alcance

- Vincular a un proyecto **ya existente** (el otro modo de asociar) no dispara ningún prellenado ni validación de coincidencia.
- No hay sincronización posterior: si el usuario edita el campo copiado, o si el proyecto origen cambia después, no se vuelve a sincronizar.
- No se valida que los valores coincidan entre proyectos ya asociados — es solo una sugerencia al momento de crear.

## Arquitectura

### 1. Modelo: `ProjectTypeAssociation#shared_field_keys`

Nueva columna `shared_field_keys` (`jsonb`, `default: []`, `null: false`) en `project_type_associations`. Lista de `key` (string) de `FieldDefinition` que el admin marcó para copiar del proyecto origen al crear el destino.

No se valida referencialmente contra `field_definitions` (podrían quedar obsoletas si se borra un campo después) — se filtran en tiempo de uso (ver "Runtime").

### 2. Admin: checklist reactivo en el form

En `app/views/admin/project_type_associations/_form.html.erb` (mismo form para "Nuevo" y "Editar"):

- Se embebe `<script type="application/json" id="field-definitions-by-type">` con, para cada `ProjectType`, su lista de `field_definitions` como `[{key, label, data_type, reference_table}]`. Generado en el controller (`Admin::ProjectTypeAssociationsController#new`/`#edit`/`#create`/`#update` en caso de re-render por error) como `@field_definitions_by_type = ProjectType.includes(:field_definitions).index_by(&:id).transform_values { |pt| pt.field_definitions.map { |f| {...} } }`.
- Un `<div id="shared-field-keys-checks">` debajo de los dos `collection_select` (`from_project_type_id`, `to_project_type_id`).
- JS plano (mismo patrón que `projects/show.html.erb`'s `filterProjects`, sin Stimulus/importmap — este proyecto no los usa): en `change` de cualquiera de los dos selects, recalcula la intersección de `field_definitions` de los dos tipos elegidos, "compatibles" (misma `key`, mismo `data_type`, y si `data_type == "reference"` también mismo `reference_table`), y redibuja un checkbox por cada key compatible con `name="project_type_association[shared_field_keys][]"` y `value` = key, mostrando el `label`.
- Al cargar la página (Editar, o Nuevo si vuelve por error de validación con selects ya elegidos), se ejecuta el mismo cálculo una vez al `DOMContentLoaded` para pintar el estado inicial, marcando (`checked`) las keys que ya estén en `project_type_association.shared_field_keys` y sigan siendo compatibles.
- Si no hay ninguna key compatible entre los dos tipos elegidos, el `div` muestra un texto simple ("No hay campos en común entre estos tipos.") en vez de checkboxes vacíos.

Controller: agregar `shared_field_keys: []` a `project_type_association_params` (strong params). Ruby ignora valores no permitidos si no se marca ningún checkbox — hay que agregar un `hidden_field_tag "project_type_association[shared_field_keys][]", ""` al inicio del form (patrón estándar de Rails para checkboxes de array) para que desmarcar todo persista como `[]` y no deje el valor viejo.

### 3. Runtime: prellenado en el quick-create

En `ProjectsController#new`, cuando `associate_with_project_id` y `project_type_association_id` estén presentes:

```ruby
def new
  @project_type = ProjectType.find(params[:project_type_id]) if params[:project_type_id]
  @project = Project.new(project_type: @project_type)
  @project_type_association_id = params[:project_type_association_id]
  @associate_with_project_id = params[:associate_with_project_id]
  prefill_shared_fields
end

private

def prefill_shared_fields
  return if @associate_with_project_id.blank? || @project_type_association_id.blank?
  association = ProjectTypeAssociation.find_by(id: @project_type_association_id)
  source = Project.find_by(id: @associate_with_project_id)
  return if association.nil? || source.nil?

  source_fields = source.project_type.field_definitions.index_by(&:key)
  target_fields = @project_type.field_definitions.index_by(&:key)

  @project.custom_fields = association.shared_field_keys.each_with_object({}) do |key, fields|
    source_field = source_fields[key]
    target_field = target_fields[key]
    next unless source_field && target_field
    next unless source_field.data_type == target_field.data_type
    next if source_field.data_type == "reference" && source_field.reference_table != target_field.reference_table

    value = source.custom_fields[key]
    fields[key] = value if value.present?
  end
end
```

El resto del form (`_field_input` por cada `field_definition`) ya lee de `project.custom_fields[field.key]`, así que no hace falta tocar la vista de `projects/new` — el valor ya llega precargado en `@project`.

### 4. Locale

Agregar a `config/locales/es.yml`:
```yaml
project_type_association:
  label: "Etiqueta"
  shared_field_keys: "Campos compartidos"
```

## Manejo de errores

- Si `association` o `source` no existen (ids inválidos/borrados), `prefill_shared_fields` no hace nada — el form queda como hoy, vacío.
- Si una key en `shared_field_keys` ya no tiene `field_definition` correspondiente en alguno de los dos tipos (se borró el campo), se ignora silenciosamente — no rompe el form.
- Si el valor de origen es `nil`/vacío, no se copia (no tiene sentido "precargar" un campo vacío).

## Testing

- **Modelo:** `ProjectTypeAssociation` acepta y persiste `shared_field_keys` como array de strings; default `[]`.
- **Controller (`Admin::ProjectTypeAssociationsController`):** crear/actualizar con `shared_field_keys` presente y ausente (checkbox destildado → queda `[]`).
- **Controller (`ProjectsController#new`):** 
  - con `associate_with_project_id` + `project_type_association_id` válidos y una key compartida con `data_type` compatible y valor presente en origen → `@project.custom_fields` trae esa key precargada.
  - key compartida pero `data_type` distinto entre origen/destino → no se precarga.
  - key en `shared_field_keys` que ya no existe en `field_definitions` → no rompe, se ignora.
  - sin `associate_with_project_id` (alta normal) → `custom_fields` vacío, comportamiento actual sin cambios.
- **JS (manual, sin test automatizado):** se verifica a mano en navegador que el checklist se recalcula al cambiar los selects y que preserva el estado marcado al recargar la página en modo Editar — este repo no tiene suite de JS, no se agrega una para esto (YAGNI).

## Resumen de archivos

- Migración: `db/migrate/<timestamp>_add_shared_field_keys_to_project_type_associations.rb`
- Modificar: `app/models/project_type_association.rb` (nada de lógica nueva, solo la columna vía schema)
- Modificar: `app/controllers/admin/project_type_associations_controller.rb` (permitir `shared_field_keys: []`, exponer `@field_definitions_by_type`)
- Modificar: `app/views/admin/project_type_associations/_form.html.erb` (checklist + JS)
- Modificar: `app/controllers/projects_controller.rb` (`prefill_shared_fields`)
- Modificar: `config/locales/es.yml`
- Test: `test/models/project_type_association_test.rb`
- Test: `test/controllers/admin/project_type_associations_controller_test.rb`
- Test: `test/controllers/projects_controller_test.rb`
