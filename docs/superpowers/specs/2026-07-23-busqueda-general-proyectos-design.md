# Búsqueda general (LIKE) en projects#index — design

## Contexto

Los campos de un proyecto son dinámicos: cada `ProjectType` define su propio conjunto de `FieldDefinition`, y los valores se guardan en `Project#custom_fields` (jsonb). No hay una lista fija de columnas contra la cual filtrar, así que un filtro tradicional "buscar por campo X" no aplica — se necesita un buscador que mire el contenido completo del proyecto sin importar qué campos tenga configurados su tipo.

## Alcance

Un campo de búsqueda de texto (`q`) en la tarjeta de filtros existente de `projects#index`, que busca (sin distinguir mayúsculas/minúsculas) tanto en `Project#name` como en el contenido completo de `custom_fields`. Se combina con AND junto a los demás filtros (Tipo/Estado/Instalador/Desde-Hasta) — todos deben cumplirse a la vez.

Fuera de alcance: resolver el campo "instalador" (que guarda solo un ID) a su nombre para buscarlo por texto — ya existe el filtro de Instalador dedicado para eso. Búsqueda en `projects#tracker` (Seguimiento) — esta ronda es específica de `projects#index`.

## Diseño

`app/controllers/projects_controller.rb`, agregar el filtro en `index` (después del filtro de fechas):

```ruby
    @projects = filter_by_query(@projects, params[:q])
```

Nuevo método privado:

```ruby
  def filter_by_query(scope, q)
    return scope if q.blank?
    term = "%#{q}%"
    scope.where("projects.name ILIKE :term OR projects.custom_fields::text ILIKE :term", term: term)
  end
```

`custom_fields::text` convierte todo el jsonb a su representación de texto plano (ej. `{"cliente": "Acme S.A.", "total": "5000"}`), así que un solo `ILIKE` alcanza para buscar en cualquier campo configurado, sin importar el tipo de proyecto ni cuántos campos tenga. `ILIKE` de Postgres ya es insensible a mayúsculas/minúsculas por sí solo, sin necesidad de `LOWER()`.

Vista — nuevo campo de texto en el formulario de filtros existente (`app/views/projects/index.html.erb`), antes del botón "Filtrar":

```erb
      <div class="col-auto">
        <%= form.label :q, "Buscar", class: "form-label" %>
        <%= form.text_field :q, value: params[:q], class: "form-control", placeholder: "Nombre, cliente, dirección..." %>
      </div>
```

## Testing

- Controlador: `index` con `q` que coincide con `Project#name` — encuentra el proyecto.
- Controlador: `index` con `q` que coincide con un valor dentro de `custom_fields` (ej. "Acme") — encuentra el proyecto, sin importar qué campo lo contenga.
- Controlador: `index` con `q` que no coincide con nada — no rompe, muestra "No hay proyectos con estos filtros."
- Controlador: `q` en minúsculas encuentra un valor guardado en mayúsculas (verifica que `ILIKE` es insensible a mayúsculas/minúsculas).
- Controlador: `q` combinado con otro filtro (ej. `project_type_id`) — ambos deben cumplirse (AND).

## Edge cases

- `q` en blanco o ausente: se comporta igual que hoy (no filtra por texto).
- `q` busca el ID guardado de un instalador (ej. "1") — puede coincidentemente encontrar proyectos cuyo campo instalador tiene ese valor, pero no es el caso de uso esperado (buscar por nombre de instalador no funciona, ya documentado como fuera de alcance).
- Caracteres especiales de SQL en `q` (ej. `%`, `_`): no se escapan explícitamente: un usuario que escriba `%` verá un comportamiento de comodín más amplio de lo esperado, pero no rompe la consulta (el placeholder `:term` sigue parametrizado, sin riesgo de inyección SQL) — no vale la pena la complejidad de escapar comodines de LIKE para un buscador interno de uso simple.
