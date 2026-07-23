# Plataforma de gestión de proyectos — Tipos de proyecto dinámicos y Gantt

**Fecha:** 2026-07-22
**Estado:** Aprobado, pendiente de plan de implementación

## Contexto y objetivo

Nueva plataforma para el seguimiento, gestión y control de proyectos de la empresa. El primer tipo de proyecto a soportar es "Instalaciones", pero el sistema debe soportar tipos de proyecto adicionales en el futuro, cada uno con sus propios campos y su propia secuencia de subprocesos (fases del Gantt), sin requerir despliegue de código nuevo.

Stack: Ruby on Rails, Postgres, despliegue futuro en Heroku. Visualización de proyectos vía diagramas de Gantt.

## Requisito clave que determina la arquitectura

Un **administrador define nuevos tipos de proyecto desde la UI** (sus campos custom y su lista de subprocesos), sin intervención de un desarrollador ni migraciones de base de datos. Esto descarta modelos de columnas fijas o tablas separadas por tipo, y obliga a un modelo de datos dirigido por metadatos.

## Enfoque elegido: JSONB + tabla de metadatos

Se evaluaron tres enfoques:

1. **JSONB + `field_definitions` (elegido).** Los valores custom de cada proyecto se guardan en una columna `jsonb`; una tabla de metadatos describe qué campos existen por tipo de proyecto, su tipo de dato, orden y visibilidad en el Gantt. Nativo de Postgres, sin gemas adicionales, agregar un campo nuevo no requiere migración.
2. **EAV clásico** (tabla `field_values` fila por campo). Descartado: joins costosos, casteo de tipos por fila, mayor complejidad de mantenimiento sin beneficio real sobre JSONB para este caso.
3. **Tabla separada por tipo de proyecto (STI o multi-tabla).** Descartado: requeriría migraciones de esquema cada vez que el admin cree un tipo nuevo, inviable en producción (Heroku) sin downtime/riesgo.

## Modelo de datos

```
ProjectType
  - id
  - name              (ej. "Instalaciones")
  - slug

FieldDefinition        (campos custom, definidos por el admin)
  - id
  - project_type_id  → ProjectType
  - key               (ej. "cliente")
  - label             (ej. "Cliente")
  - data_type         (text | date | percent | reference)
  - reference_table    (solo si data_type=reference, ej. "installers")
  - position           (orden de despliegue)
  - show_in_gantt       (bool: aparece como columna del Gantt)

StageTemplate            (subprocesos fijos por tipo, ej. "Producción")
  - id
  - project_type_id  → ProjectType
  - name
  - position           (orden fijo de la secuencia)

Project
  - id
  - project_type_id  → ProjectType
  - name
  - custom_fields      (jsonb — valores de los FieldDefinition de este tipo)
  - status

ProjectStage              (barras del Gantt, generadas desde StageTemplate al crear el Project)
  - id
  - project_id        → Project
  - stage_template_id  → StageTemplate (referencia a la etapa origen)
  - name               (copiado del template al crear, congelado)
  - start_date
  - end_date
  - progress_percent
  - assigned_user_id   (responsable)

Installer                 (catálogo, crece con el tiempo)
  - id
  - name
```

### Flujo de creación de proyecto

Al crear un `Project`, se leen los `StageTemplate` de su `project_type` (ordenados por `position`) y se copian como `ProjectStage` — las barras reales del Gantt, cada una con sus propias fechas, responsable y % de avance. Los campos custom (Cliente, Vendedor, Dirección, Contacto, Instalador, etc.) se guardan en `Project.custom_fields`; `FieldDefinition` le indica a la UI cómo renderizarlos y si aparecen como columna en el Gantt.

Ejemplo concreto para "Instalaciones":
- Campos: Proyecto, Cliente, Vendedor, Dirección, Contacto (todos `text`), Instalador (`reference` → tabla `installers`), Progreso (`percent`), Inicio/Fin (`date`).
- Subprocesos (StageTemplate, en orden): Diseño-Aprobación → Revisión Inicial → Producción → Entrega → Instalación.

## Renderizado dinámico y validación

**Columnas del Gantt:** el panel izquierdo muestra siempre las columnas estándar (Nombre, Inicio, Fin, Responsable, % Avance) más las `FieldDefinition` del `project_type` con `show_in_gantt = true`, ordenadas por `position`. Todos los proyectos del mismo tipo comparten el mismo conjunto de columnas.

**Formularios de proyecto:** se generan iterando las `FieldDefinition` del tipo — cada `data_type` mapea a un input (texto, fecha, número %, o `<select>` poblado desde `reference_table`). No hay formularios hardcodeados por tipo de proyecto.

**Validación:** un validator en el modelo `Project` recorre las `FieldDefinition` de su `project_type` y valida que cada valor en `custom_fields` coincida con su `data_type` (fecha válida, porcentaje 0-100, referencia existente). Centralizado en el modelo, no duplicado por controlador.

**Admin UI de tipos de proyecto:** CRUD anidado (nested attributes de Rails) para `ProjectType` con sus `FieldDefinition` y `StageTemplate`, con control de orden (`position`). Sin gemas de formularios dinámicos.

## Casos borde

- **Editar un `StageTemplate` con proyectos ya existentes:** los `ProjectStage` ya creados no cambian retroactivamente — son una copia congelada tomada al crear el `Project`. El cambio solo afecta a proyectos nuevos.
- **Borrar una `FieldDefinition` con datos guardados:** el valor queda huérfano dentro del `jsonb` pero no rompe nada; simplemente deja de mostrarse. No se requiere lógica de migración de datos para el alcance actual.
- **Visualización del Gantt (librería JS):** decisión de implementación (Frappe Gantt, gantt-elastic u otra vía importmap/esbuild), fuera del alcance del modelo de datos — se define en el plan de implementación.

## Pruebas

- Validator de `custom_fields` contra `FieldDefinition` (tipos correctos, referencias válidas).
- Copia de `StageTemplate` → `ProjectStage` al crear un `Project` (orden, congelamiento de nombre).

Tests de modelo (framework de testing del proyecto) cubren ambos puntos; no se requiere más para el alcance actual.

## Fuera de alcance (este spec)

- Elección de librería de visualización Gantt en frontend.
- Autenticación/roles de usuario.
- Despliegue a Heroku (futuro, no bloqueante para este diseño).
