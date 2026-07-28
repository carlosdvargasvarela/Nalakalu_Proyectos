# Glowup de login y panel admin — design

## Contexto

El login (`devise/sessions/new.html.erb`) es el scaffold por defecto de Devise, sin ninguna clase de Bootstrap (`<p>`/`<div class="field">` crudos). Las ~15 vistas de `/admin/*` (tipos de proyecto, campos, subprocesos, tipos de bitácora, instaladores, usuarios) usan Bootstrap pero de forma cruda: la mayoría son un `<h1>` pelado seguido de una lista o un formulario, sin ninguna tarjeta que las contenga (solo `admin/project_types/show.html.erb` ya usa tarjetas, para sus 3 secciones internas).

Pedido: un pulido visual conservador — mismo esquema de color y componentes de Bootstrap que ya tiene la app (`--bs-primary: #2c3e50`, `border-radius` redondeado, definidos en `app/assets/stylesheets/application.css`), pero con mejor jerarquía (tarjetas, spacing, badges de color) en vez de una identidad visual nueva.

## Alcance

- **Login** (`devise/sessions/new.html.erb`): tarjeta centrada y angosta en vez del formulario crudo de Devise.
- **Todo `/admin/*`**: tipos de proyecto (índice, nuevo, editar — `show.html.erb` no se toca, ver abajo), campos, subprocesos, tipos de bitácora, instaladores, usuarios (índice, nuevo, editar).
- **Mecanismo**: un helper `admin_card(title) { ... }` en `ApplicationHelper` que envuelve cualquier contenido en una tarjeta Bootstrap consistente (header + body). Cada vista que hoy es un `<h1>` pelado + contenido pasa a ser `<%= admin_card("Título") do %> ... <% end %>` — el título reemplaza al `<h1>` suelto (queda en el header de la tarjeta), no se duplican ambos.
- **CSS global**: una regla de sombra sutil en `.card`/`.card-header` en `application.css` — esto también mejora, gratis y sin tocar el archivo, las 3 tarjetas que ya existen en `admin/project_types/show.html.erb` (Campos/Subprocesos/Tipos de Bitácora) y las tarjetas de `projects/show.html.erb` (Cronograma/Bitácora/Historial).
- **Badges de rol**: `admin/users/index.html.erb` gana un badge de color por rol (reusa el patrón `STATUS_BADGE_CLASSES` que ya existe en `ApplicationHelper`).
- `admin/users/_form.html.erb` pasa de "formulario + `<hr>` + accesos" a dos tarjetas separadas (Datos del usuario / Accesos a proyectos), usando el mismo helper.

**No se toca**: `admin/project_types/show.html.erb` (ya tiene tarjetas, solo se beneficia del CSS global), el resto de `projects/*` (fuera de este pedido), ningún dato/lógica de negocio, ningún test de comportamiento — solo estructura visual. La única vista con un test que verifica markup específico (`h2`, texto de botón) es el login; ese contrato se preserva.

## Diseño

### Helper `admin_card`

```ruby
# app/helpers/application_helper.rb — agregar
def admin_card(title, &block)
  content_tag(:div, class: "card shadow-sm mb-4") do
    content_tag(:div, title, class: "card-header fw-semibold") +
      content_tag(:div, capture(&block), class: "card-body")
  end
end
```

### CSS

```css
/* app/assets/stylesheets/application.css — agregar */
.card {
  box-shadow: 0 0.125rem 0.5rem rgba(0, 0, 0, 0.06);
  border: 1px solid rgba(0, 0, 0, 0.06);
}

.card-header {
  background-color: #f8f9fa;
  font-weight: 600;
}
```

### Login

```erb
<div class="row justify-content-center">
  <div class="col-md-5 col-lg-4">
    <div class="card shadow-sm mt-5">
      <div class="card-body p-4">
        <div class="text-center mb-4">
          <i class="bi bi-person-circle" style="font-size: 2.5rem; color: var(--bs-primary);"></i>
          <h2 class="h4 mt-2 mb-0">Iniciar sesión</h2>
        </div>

        <%= form_for(resource, as: resource_name, url: session_path(resource_name)) do |f| %>
          <div class="mb-3">
            <%= f.label :email, "Correo electrónico", class: "form-label" %>
            <%= f.email_field :email, autofocus: true, autocomplete: "email", class: "form-control" %>
          </div>

          <div class="mb-3">
            <%= f.label :password, "Contraseña", class: "form-label" %>
            <%= f.password_field :password, autocomplete: "current-password", class: "form-control" %>
          </div>

          <% if devise_mapping.rememberable? %>
            <div class="form-check mb-3">
              <%= f.check_box :remember_me, class: "form-check-input" %>
              <%= f.label :remember_me, "Recordarme", class: "form-check-label" %>
            </div>
          <% end %>

          <%= f.submit "Iniciar sesión", class: "btn btn-primary w-100" %>
        <% end %>
      </div>
    </div>
  </div>
</div>
```

`<h2>` con el texto exacto "Iniciar sesión" se preserva (test `authentication_test.rb` lo verifica), igual que el texto del submit.

### Patrón de wrap para el resto de `/admin`

Cada `new.html.erb`/`edit.html.erb` que hoy es:
```erb
<h1>Nuevo X</h1>
<%= render "form", ... %>
```
pasa a delegar el título al propio `_form.html.erb`, que se envuelve así:
```erb
<%= admin_card(x.persisted? ? "Editar X" : "Nuevo X") do %>
  <%= form_with model: [...] do |form| %>
    ...
  <% end %>
<% end %>
```
Los `new.html.erb`/`edit.html.erb` quedan reducidos a una sola línea (`<%= render "form", ... %>`), igual que ya son hoy salvo por el `<h1>` que se quita.

Para `field_definitions`/`stage_templates` (título con contexto del `project_type`), el título pasa `"Nuevo campo — #{project_type.name}"` / `"Editar campo — #{project_type.name}"` al helper.

Para `admin/project_types/index.html.erb` y `admin/installers/index.html.erb` (listas sin formulario), el `<h1>` + lista se envuelve entero en `admin_card("Título")`.

### `admin/users`

`index.html.erb`: tabla envuelta en `admin_card("Usuarios")`; cada fila de rol usa un badge de color nuevo:
```ruby
# app/helpers/application_helper.rb — agregar junto a STATUS_BADGE_CLASSES
ROLE_BADGE_CLASSES = { "admin" => "bg-primary", "gerente" => "bg-info text-dark", "visor" => "bg-secondary" }.freeze

def role_badge_class(role)
  ROLE_BADGE_CLASSES.fetch(role, "bg-light text-dark")
end
```
```erb
<span class="badge <%= role_badge_class(user.role) %>"><%= role_label(user.role) %></span>
```

`_form.html.erb`: se separa en dos `admin_card`, uno para los datos del usuario (email/rol/contraseña) y otro para "Accesos a proyectos" (solo si `user.persisted?`) — mismo contenido que hoy, solo reorganizado en dos tarjetas en vez de un formulario + `<hr>` + tabla suelta.

## Testing

- Ningún test de comportamiento cambia — es un cambio puramente de presentación. Los tests existentes de `admin/*_controller_test.rb` que verifican texto de botones (`assert_select "input[value=?]", "Crear Instalador"`) siguen intactos porque no se tocan los campos/labels de los formularios, solo lo que los envuelve.
- `authentication_test.rb`'s `"sign-in page is in Spanish"` sigue pasando sin cambios (mismo `<h2>Iniciar sesión</h2>`, mismo texto de submit).
- Verificación manual (no automatizada, es un cambio visual): cargar cada página de `/admin/*` y el login, confirmar que las tarjetas se ven bien, que no quedan `<h1>` duplicados ni títulos faltantes.

## Edge cases

- `admin/project_types/show.html.erb` ya tiene 3 tarjetas con drag-and-drop (JS que depende de IDs específicos) — no se toca su HTML, solo hereda la sombra vía CSS global. Ningún riesgo de romper el drag-and-drop.
- El helper `admin_card` usa `capture(&block)`, que requiere ser llamado desde un contexto de vista (ERB), no desde un controlador ni un test unitario de helper aislado — coherente con cómo ya se usan otros helpers de esta app (`status_badge`, etc.), sin necesidad de tests de helper dedicados.
