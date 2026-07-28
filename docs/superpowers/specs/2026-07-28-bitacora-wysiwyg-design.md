# Bitácora con editor WYSIWYG (Action Text) — design

## Contexto

Dos hallazgos del piloto sobre la bitácora recién lanzada ([[2026-07-28-bitacora-y-log-de-cambios-design]]):

1. **Bug**: el timestamp de cada nota mostraba `Translation missing: es.date.abbr_month_names` en vez del mes abreviado — ya corregido por separado (`es.yml` no tenía `date.abbr_month_names`).
2. **Pedido**: que el campo de texto de la nota sea WYSIWYG (negrita, itálica, listas, enlaces) en vez de texto plano.

Este spec cubre solo el punto 2.

## Alcance

Reemplazar el `<textarea>` de la bitácora por un editor Action Text (Trix), el editor rico que viene con Rails — sin gemas nuevas, ya está resuelto por Bundler vía la gema `rails` (`actiontext`/`activestorage` aparecen en `Gemfile.lock` como dependencias transitivas, y `config/application.rb` ya hace `require "rails/all"`, que las carga).

Esta app no usa el pipeline de `importmap-rails` (no hay `config/importmap.rb` ni `app/javascript/`, pese a que la gema está en el Gemfile) — todo el JS/CSS de terceros se carga por CDN (`content_for :head`, ver Gantt en `projects/show.html.erb`). Se sigue ese mismo patrón: Trix se carga por CDN (`trix.css` + `trix.umd.min.js`), sin tocar el pipeline de assets.

`LogEntry#body` deja de ser una columna `text` y pasa a ser `has_rich_text :body` (el patrón estándar de Action Text: el contenido se guarda en una tabla nueva `action_text_rich_texts`, asociación polimórfica). La única nota que ya existe en el piloto se migra en la misma migración que borra la columna vieja.

Fuera de alcance: adjuntar imágenes/archivos en las notas (Action Text lo soporta pero no se pidió — requeriría wiring adicional de `@rails/actiontext` para direct upload, que no se agrega). Editar notas existentes (ya estaba fuera de alcance del feature original). Aplicar WYSIWYG a algún otro campo de texto de la app (solo a `LogEntry#body`).

## Diseño

### Migraciones (ActiveStorage + Action Text)

Action Text requiere las tablas estándar de ActiveStorage (aunque no se usen adjuntos, `ActionText::RichText` las referencia estructuralmente) y su propia tabla. Usando bigint ids simples, consistente con el resto del schema de esta app (no hay tablas con uuid):

```ruby
# db/migrate/..._create_active_storage_tables.rb
class CreateActiveStorageTables < ActiveRecord::Migration[7.2]
  def change
    create_table :active_storage_blobs do |t|
      t.string   :key,          null: false
      t.string   :filename,     null: false
      t.string   :content_type
      t.text     :metadata
      t.string   :service_name, null: false
      t.bigint   :byte_size,    null: false
      t.string   :checksum
      t.datetime :created_at,   precision: 6, null: false

      t.index [:key], unique: true
    end

    create_table :active_storage_attachments do |t|
      t.string     :name,     null: false
      t.references :record,   null: false, polymorphic: true, index: false
      t.references :blob,     null: false

      t.datetime :created_at, precision: 6, null: false

      t.index [:record_type, :record_id, :name, :blob_id], name: "index_active_storage_attachments_uniqueness", unique: true
      t.foreign_key :active_storage_blobs, column: :blob_id
    end

    create_table :active_storage_variant_records do |t|
      t.belongs_to :blob, null: false, index: false
      t.string :variation_digest, null: false

      t.index [:blob_id, :variation_digest], name: "index_active_storage_variant_records_uniqueness", unique: true
      t.foreign_key :active_storage_blobs, column: :blob_id
    end
  end
end
```

```ruby
# db/migrate/..._create_action_text_tables.rb
class CreateActionTextTables < ActiveRecord::Migration[7.2]
  def change
    create_table :action_text_rich_texts do |t|
      t.string     :name, null: false
      t.text       :body, size: :long
      t.references :record, null: false, polymorphic: true, index: false

      t.timestamps

      t.index [:record_type, :record_id, :name], name: "index_action_text_rich_texts_uniqueness", unique: true
    end
  end
end
```

### Migración de datos: `log_entries.body` → Action Text

```ruby
# db/migrate/..._migrate_log_entry_body_to_action_text.rb
class MigrateLogEntryBodyToActionText < ActiveRecord::Migration[7.2]
  def up
    connection.select_all(
      "SELECT id, body, created_at, updated_at FROM log_entries WHERE body IS NOT NULL AND body != ''"
    ).each do |row|
      escaped_body = "<div>#{ERB::Util.html_escape(row['body'])}</div>"
      connection.execute(<<~SQL)
        INSERT INTO action_text_rich_texts (name, body, record_type, record_id, created_at, updated_at)
        VALUES ('body', #{connection.quote(escaped_body)}, 'LogEntry', #{row['id']}, #{connection.quote(row['created_at'])}, #{connection.quote(row['updated_at'])})
      SQL
    end

    remove_column :log_entries, :body
  end

  def down
    add_column :log_entries, :body, :text

    connection.select_all(
      "SELECT record_id, body FROM action_text_rich_texts WHERE record_type = 'LogEntry' AND name = 'body'"
    ).each do |row|
      connection.execute(
        "UPDATE log_entries SET body = #{connection.quote(ActionView::Base.full_sanitizer.sanitize(row['body']))} WHERE id = #{row['record_id']}"
      )
    end
  end
end
```

`up` runs before Rails autoloads `LogEntry` with its new `has_rich_text :body`, so it reads/writes via raw SQL rather than the model — this avoids a chicken-and-egg problem (the model change and the schema change land in the same deploy). `down` strips HTML tags back to plain text on rollback (lossy, acceptable for a rollback path).

### Model

```ruby
# app/models/log_entry.rb
class LogEntry < ApplicationRecord
  belongs_to :project
  belongs_to :user
  belongs_to :log_entry_type

  has_rich_text :body

  validates :body, presence: true
end
```

`validates :body, presence: true` keeps working unchanged — `ActionText::RichText#blank?` delegates to the plain-text content, so an empty Trix editor still fails validation the same way an empty string did before.

### View

`app/views/projects/show.html.erb`: load Trix from CDN in the existing `content_for :head` block (same block that already loads frappe-gantt's CSS):

```erb
<% content_for :head do %>
  <link href="https://cdn.jsdelivr.net/npm/frappe-gantt@1.2.2/dist/frappe-gantt.css" rel="stylesheet">
  <link href="https://cdn.jsdelivr.net/npm/trix@2.1.6/dist/trix.css" rel="stylesheet">
  <script src="https://cdn.jsdelivr.net/npm/trix@2.1.6/dist/trix.umd.min.js"></script>
<% end %>
```

Bitácora form, replace the `text_area` with `rich_text_area`:

```erb
<%= f.rich_text_area :body, class: "trix-content mb-0" %>
```

(Rails' `rich_text_area` renders a hidden input plus a `<trix-editor>` custom element; Trix's own CSS handles the toolbar/editor box styling, so this doesn't need the `form-control form-control-sm` classes the old textarea used — those are for native `<textarea>` elements.)

The entry list already does `<%= entry.body %>` — unchanged. `ActionText::RichText#to_s` returns sanitized, `html_safe` HTML, so formatted notes (bold/lists/links) render correctly with no further view change.

### Tests

- `test/models/log_entry_test.rb`: existing "valid with ... body" and "invalid without body" tests are unchanged in behavior — assigning `body: "some string"` to a `has_rich_text` attribute and checking `.valid?`/`.invalid?` works identically to a plain string column from the test's point of view.
- `test/controllers/log_entries_controller_test.rb`: existing tests unchanged — creating via `params: { log_entry: { body: "...", ... } }` and reading `.body` still works (Action Text accepts plain-string mass-assignment, wraps it).
- `test/controllers/projects_controller_test.rb`: the bitácora rendering test (`assert_select "body", /Nota visible en la bitácora/`) still passes — the plain text still appears inside the rendered (sanitized) HTML.
- New: a model test asserting `LogEntry#body` round-trips actual HTML formatting, e.g. create with `body: "<strong>Urgente</strong>"` and assert `log_entry.body.to_s.include?("<strong>")` — this is the one behavior that's genuinely new (rich content persisting as HTML, not just plain text) and isn't covered by the reused tests above.
- Migration itself is not unit-tested (no precedent for migration tests in this codebase, per the earlier `LogEntryType` backfill migration) — verified manually via `bin/rails runner` before/after running it, checking the pre-existing pilot note's content survives the migration.

## Edge cases

- The one existing "Prueba" note in the pilot database: migrated via the data migration, verified manually (not via automated test, per the note above) that it appears as `<div>Prueba</div>` in `action_text_rich_texts` and renders correctly in `projects#show` after the migration runs.
- A `LogEntry` created with only whitespace as body: `ActionText::Content#blank?` treats whitespace-only content as blank (matches old `presence: true` behavior on a text column), so the validation still rejects it.
- Trix requires JavaScript to render the rich toolbar; without JS, the underlying hidden `<input>` still submits whatever HTML was last saved into it via the server-rendered `<trix-editor>`'s initial content — same graceful-degradation story as any other JS-enhanced form in this app (e.g. drag-reorder in the admin panel), not something this feature needs to solve differently.
