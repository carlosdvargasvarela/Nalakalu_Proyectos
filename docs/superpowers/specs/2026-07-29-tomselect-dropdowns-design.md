# TomSelect en los selects grandes — design

## Contexto

Varios `<select>` de la app pueden llegar a tener muchas opciones (todo el catálogo de `Responsible`, todos los `Project`, todos los `User` sin vincular) y hoy son `<select>` nativos sin buscador — hay que scrollear la lista entera para encontrar una opción. Se pide agregar [TomSelect](https://tom-select.js.org/) (buscar-mientras-escribís) a esos selects grandes específicamente, dejando los chicos (Estado, Sí/No, Tipo de responsable/asociación — 2 a 5 opciones fijas) como `<select>` nativo.

La app no usa import maps ni ningún bundler de JS (`importmap-rails` está en el Gemfile pero nunca se configuró: no hay `config/importmap.rb` ni `app/javascript/`) — todo el JS de terceros (Bootstrap, frappe-gantt, trix) se carga hoy vía CDN con `<script src="...">`/`<link rel="stylesheet">` directos. TomSelect sigue el mismo patrón, sin agregar bundler nuevo.

## Alcance

Selects que pasan a TomSelect (progressive enhancement sobre el `<select>` ya renderizado, sin cambiar el HTML del formulario ni los params que se envían):

1. `_project_type_section.html.erb` — filtro "Responsable".
2. `_project_type_section.html.erb` — bulk-assign "Asignar a los seleccionados".
3. `tracker.html.erb` — filtro "Responsable".
4. `projects/show.html.erb` — "Responsable" del formulario de asignación (tarjeta Responsables).
5. `projects/show.html.erb` — "Proyecto" del formulario de vincular-existente (tarjeta Asociaciones) — este ya tiene el filtro dependiente por tipo de asociación (`data-project-type-id`) agregado en la vuelta anterior; TomSelect tiene que convivir con esa lógica, no romperla.
6. `admin/responsibles/_form.html.erb` — "Usuario vinculado".

Quedan como `<select>` nativo (2-5 opciones fijas, no se benefician de un buscador): Estado, Sí/No (checkboxes en realidad), Tipo de responsable, Tipo de asociación, Tipo de proyecto.

Fuera de alcance: cambiar los `<select>` de checkboxes existentes (Tipos de proyecto habilitados); cualquier cambio de datos, lógica de negocio o validaciones; un import map o bundler de JS nuevo (se sigue el patrón CDN ya establecido).

## Diseño

### Cargar TomSelect

En `app/views/layouts/application.html.erb`, junto a Bootstrap:

```erb
<link href="https://cdn.jsdelivr.net/npm/tom-select@2.3.1/dist/css/tom-select.bootstrap5.min.css" rel="stylesheet">
```

y antes de cerrar `</body>`, junto al script de Bootstrap:

```erb
<script src="https://cdn.jsdelivr.net/npm/tom-select@2.3.1/dist/js/tom-select.complete.min.js"></script>
```

(La build `bootstrap5` de su CSS ya viene pensada para convivir visualmente con `form-select`, sin CSS propio adicional.)

### Marcar qué selects se mejoran

Cada uno de los 6 selects de la sección "Alcance" gana la clase `js-tomselect` (además de `form-select`, que se mantiene — TomSelect no depende de esa clase, es puramente nuestra para saber a cuáles inicializar). Ej.:

```erb
<%= form.select :responsible_id, ..., {}, class: "form-select js-tomselect" %>
```

### Init genérico (los 5 selects "simples")

Un solo script, agregado al final de `application.html.erb` (junto al de Bootstrap), inicializa cualquier select marcado — no hace falta repetir código en cada vista:

```erb
<script>
  document.addEventListener("DOMContentLoaded", function () {
    document.querySelectorAll("select.js-tomselect").forEach(function (el) {
      if (!el.tomselect) new TomSelect(el, { create: false, allowEmptyOption: true });
    });
  });
</script>
```

(`allowEmptyOption: true` conserva la opción en blanco/"Todos"/"Ninguno" que ya usan estos selects vía `include_blank`.)

### El caso especial: "Proyecto" dependiente de "Tipo de asociación"

El script de filtrado agregado en la vuelta anterior (`app/views/projects/show.html.erb`) manipulaba `option.hidden` directamente sobre el `<select>` nativo. Con TomSelect de por medio, ese `<select>` queda oculto (TomSelect lo mantiene como fuente de verdad para el submit, pero la UI real es su propio widget) — hay que repoblar las opciones de TomSelect explícitamente en vez de esconder `<option>`s.

Reemplazo del script de filtrado:

```erb
<script>
  document.addEventListener("DOMContentLoaded", function () {
    var typeSelect = document.getElementById("project_association_project_type_association_id");
    var otherSelect = document.getElementById("project_association_other_project_id");
    if (!typeSelect || !otherSelect || !otherSelect.tomselect) return;

    var allProjectOptions = Array.from(otherSelect.options)
      .filter(function (o) { return o.value; })
      .map(function (o) { return { value: o.value, text: o.text, projectTypeId: o.dataset.projectTypeId }; });

    function filterProjects() {
      var selectedValue = typeSelect.tomselect ? typeSelect.tomselect.getValue() : typeSelect.value;
      var selectedOption = selectedValue ? typeSelect.querySelector('option[value="' + selectedValue + '"]') : null;
      var otherProjectTypeId = selectedOption ? selectedOption.dataset.otherProjectTypeId : null;

      var ts = otherSelect.tomselect;
      ts.clear();
      ts.clearOptions();
      allProjectOptions
        .filter(function (o) { return !otherProjectTypeId || o.projectTypeId === otherProjectTypeId; })
        .forEach(function (o) { ts.addOption(o); });
      ts.refreshOptions(false);
    }

    if (typeSelect.tomselect) {
      typeSelect.tomselect.on("change", filterProjects);
    } else {
      typeSelect.addEventListener("change", filterProjects);
    }
    filterProjects();
  });
</script>
```

Claves de por qué esto es seguro:
- Lee `data-other-project-type-id` directo del `<option>` original del `<select>` nativo (que sigue existiendo en el DOM, TomSelect no lo borra) — no depende de que TomSelect haya copiado ese atributo a su estructura interna.
- `ts.clearOptions()` + `ts.addOption()` + `ts.refreshOptions(false)` es la forma documentada de TomSelect para repoblar opciones dinámicamente sin recrear la instancia.
- "Tipo de asociación" queda como `<select>` nativo (fuera de alcance, ver arriba), así que `typeSelect.tomselect` va a ser `undefined` en la práctica — el código contempla igual el caso por las dudas (si en el futuro se decide agrandarlo también), sin que rompa nada hoy.

Este script reemplaza al que ya existe (mismo lugar, misma vista) — no se agrega uno nuevo al lado, se reemplaza.

## Testing

- No hay forma de testear la interacción real de TomSelect (JS de terceros, comportamiento de UI) con Minitest/Capybara sin un navegador real — igual que ya pasa con el resto del JS de esta app (Gantt, drag-reorder), no se agregan tests de comportamiento de TomSelect en sí.
- Se agrega un test por vista verificando que el `<select>` correspondiente tiene la clase `js-tomselect` — confirma que el markup quedó bien marcado, no que TomSelect se inicialice (eso se verifica a mano en el navegador).
- El test ya existente que verifica los `data-*` attributes del selector dependiente (de la vuelta anterior) no cambia — sigue siendo válido, ya que el HTML de las `<option>` no cambia, solo se les agrega la clase al `<select>` padre.

## Edge cases

- Un select con una sola opción (`include_blank` + 1 sola opción real, ej. un catálogo de responsables recién empezado): TomSelect igual funciona, solo que el buscador no aporta mucho con tan pocas opciones — no hace falta ninguna condición especial para ese caso.
- Verificación manual en el navegador: como es JS de terceros con interacción real de UI, este cambio necesita probarse a mano después de implementado (escribir en el buscador, confirmar que el selector dependiente de Proyecto sigue filtrando bien con TomSelect encima) — no se puede afirmar que "funciona" solo con los tests automatizados.
