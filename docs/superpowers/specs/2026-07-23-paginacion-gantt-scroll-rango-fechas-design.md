# Paginación, Gantt con scroll y filtro de rango de fechas — design

## Contexto

La pantalla `projects#index` (Proyectos) ya no escala bien: con más de 10 proyectos la tabla "Listado" se hace muy larga, y el Gantt general crece sin límite en altura. Además, un proyecto que arranca varios meses en el futuro estira la escala de tiempo del Gantt (frappe-gantt calcula automáticamente el rango mínimo/máximo entre todos los proyectos mostrados), haciendo que los proyectos cercanos se vean apretados. Esta ronda agrega: (1) paginación de la tabla, (2) altura máxima con scroll en el Gantt a partir de ~15 proyectos, y (3) un filtro opcional "Desde/Hasta" que acota qué proyectos se muestran tanto en la tabla como en el Gantt.

## Alcance

1. **Paginación** — 20 proyectos por página en la tabla "Listado", con controles Anterior/Siguiente + números de página (Bootstrap `.pagination`, sin gemas nuevas).
2. **Gantt con altura máxima y scroll** — el contenedor `#gantt` obtiene `max-height` fijo (~630px, equivalente a ~15 filas) y `overflow-y: auto` siempre presentes vía CSS. El Gantt sigue mostrando **todos** los proyectos filtrados (no solo los de la página actual de la tabla) — sin scroll si son 15 o menos, con scroll automático si son más.
3. **Filtro "Desde/Hasta"** — dos campos de fecha nuevos (`from_date`/`to_date`) en el formulario de filtros existente. Un proyecto se incluye si el rango de sus subprocesos se solapa con el rango elegido. Afecta tanto la tabla como el Gantt (mismo criterio que los filtros existentes de Tipo/Estado/Instalador). Sin ninguno de los dos campos, el comportamiento es idéntico al actual (se muestra todo).

Fuera de alcance: paginación del Gantt (el Gantt siempre muestra el conjunto completo filtrado, ya decidido), un selector de "ventana automática de N meses" (se eligió el filtro manual en su lugar), cambios a `projects#tracker` (Seguimiento) — esta ronda es específica de `projects#index`.

## 1. Paginación

La vista ya carga el conjunto filtrado completo en memoria (`projects_list = @projects.to_a`) para calcular las KPIs (Total/Vencidos/Finalizados) y las tareas del Gantt — ambos deben seguir viendo el conjunto **completo**, no solo la página actual. Por eso la paginación es una porción (slice) en Ruby sobre ese arreglo ya cargado, no un `LIMIT`/`OFFSET` en SQL — evita una segunda consulta y no interactúa con el `JOIN`+`DISTINCT` que introduce el filtro de fechas (sección 3).

`app/controllers/projects_controller.rb`, en `index`, agregar después de las líneas de filtrado existentes:

```ruby
    @page = [params[:page].to_i, 1].max
```

`app/views/projects/index.html.erb`, después de `projects_list = @projects.to_a`:

```erb
  <%
    projects_list = @projects.to_a
    per_page = 20
    total_pages = (projects_list.size / per_page.to_f).ceil
    page_projects = projects_list.drop((@page - 1) * per_page).first(per_page)
  %>
```

`gantt_tasks`, `gantt_colors` y las KPIs siguen iterando sobre `projects_list` (completo, sin cambios). El bloque `<tbody>` de la tabla pasa a iterar sobre `page_projects` en lugar de `projects_list`:

```erb
        <tbody>
          <% page_projects.each do |project| %>
            <tr>
              <!-- contenido de la fila sin cambios -->
            </tr>
          <% end %>
        </tbody>
```

Controles de paginación debajo de la tabla, dentro de la misma card, preservando los filtros activos vía `request.query_parameters`:

```erb
      <% if total_pages > 1 %>
        <nav class="p-3">
          <ul class="pagination mb-0">
            <li class="page-item <%= "disabled" if @page <= 1 %>">
              <%= link_to "Anterior", projects_path(request.query_parameters.merge(page: @page - 1)), class: "page-link" %>
            </li>
            <% (1..total_pages).each do |n| %>
              <li class="page-item <%= "active" if n == @page %>">
                <%= link_to n, projects_path(request.query_parameters.merge(page: n)), class: "page-link" %>
              </li>
            <% end %>
            <li class="page-item <%= "disabled" if @page >= total_pages %>">
              <%= link_to "Siguiente", projects_path(request.query_parameters.merge(page: @page + 1)), class: "page-link" %>
            </li>
          </ul>
        </nav>
      <% end %>
```

Cualquier envío del formulario de filtros (que no incluye un campo oculto de página) vuelve naturalmente a la página 1, sin lógica adicional.

## 2. Gantt con scroll

`app/views/projects/index.html.erb`, agregar `max-height`/`overflow-y` al div que contiene el Gantt:

```erb
      <div id="gantt" class="mb-0" style="max-height: 630px; overflow-y: auto;"></div>
```

630px es una aproximación basada en la altura de fila por defecto de frappe-gantt (`bar_height` + `padding` ≈ 38px/fila) más la cabecera (~60px) para ~15 filas — no requiere ninguna condición en Ruby; con 15 proyectos o menos la altura natural del SVG generado es menor que el máximo y no aparece scroll.

## 3. Filtro "Desde/Hasta"

`app/controllers/projects_controller.rb`, agregar el filtrado (después del filtro de instalador existente):

```ruby
    @projects = filter_by_date_range(@projects, params[:from_date], params[:to_date])
```

Nuevo método privado, junto a `filter_by_no_installer`:

```ruby
  def filter_by_date_range(scope, from_date, to_date)
    return scope if from_date.blank? && to_date.blank?
    scope = scope.joins(:project_stages).distinct
    scope = scope.where("project_stages.end_date >= ?", from_date) if from_date.present?
    scope = scope.where("project_stages.start_date <= ?", to_date) if to_date.present?
    scope
  end
```

Un proyecto queda incluido si **algún** subproceso suyo termina en o después de `from_date` y **algún** subproceso suyo empieza en o antes de `to_date` — esto es la condición de solapamiento de rangos, evaluada contra las columnas reales `start_date`/`end_date` de `project_stages` (no contra `Project#start_date`/`#end_date`, que son valores calculados en Ruby, no columnas). El `.distinct` evita duplicados cuando un proyecto tiene varios subprocesos que matchean el join.

Vista — dos campos de fecha nuevos en el formulario de filtros existente:

```erb
      <div class="col-auto">
        <%= form.label :from_date, "Desde", class: "form-label" %>
        <%= form.date_field :from_date, value: params[:from_date], class: "form-control" %>
      </div>
      <div class="col-auto">
        <%= form.label :to_date, "Hasta", class: "form-label" %>
        <%= form.date_field :to_date, value: params[:to_date], class: "form-control" %>
      </div>
```

## Testing

- Controlador: `index` con 25 proyectos — página 1 muestra 20, página 2 muestra 5; KPIs y cantidad de tareas del Gantt siguen contando las 25.
- Controlador: `index` con `from_date`/`to_date` — incluye un proyecto cuyo rango se solapa parcialmente, excluye uno completamente antes o después del rango.
- Controlador: `index` sin `from_date` ni `to_date` — se comporta igual que antes (todos los proyectos que cumplen los demás filtros).
- Vista: con 16 proyectos, el div `#gantt` renderiza el estilo `max-height`/`overflow-y: auto` (siempre presente, no condicional).
- Vista: los controles de paginación no aparecen cuando hay 20 proyectos o menos.

## Edge cases

- `page` fuera de rango (por ejemplo `page=99` con solo 2 páginas): `page_projects` queda vacío (el `.drop` en un arreglo más corto que el offset devuelve `[]`), la tabla se ve vacía en esa página en vez de romperse — no se agrega redirección automática a la última página válida (no fue pedido, y es un caso de borde raro de edición manual de URL).
- `from_date` posterior a `to_date`: la condición simplemente no matchea ningún subproceso (comportamiento correcto sin necesitar validación extra — no es un error del usuario que rompa la página, solo devuelve una lista vacía).
- Proyecto sin ningún `project_stage` con fechas (`start_date`/`end_date` nulos): se sigue mostrando siempre, sin importar el rango Desde/Hasta elegido (corrección post-lanzamiento: la mayoría de los proyectos reales todavía no tienen fechas cargadas en sus subprocesos; excluirlos del filtro los hacía desaparecer apenas se usaba Desde/Hasta). Solo se excluye un proyecto que **sí** tiene fechas en sus subprocesos pero ninguna se solapa con el rango elegido.
