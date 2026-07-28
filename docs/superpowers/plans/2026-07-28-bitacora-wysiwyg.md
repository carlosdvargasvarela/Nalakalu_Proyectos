# Bitácora WYSIWYG (Action Text) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the bitácora's plain `<textarea>` with a Trix (Action Text) rich-text editor, migrating the one existing pilot note.

**Architecture:** Rails' built-in Action Text (`has_rich_text`), no new gem dependency (already resolved transitively via the `rails` gem and `require "rails/all"`). Trix's JS/CSS load via CDN, following this app's existing pattern for third-party frontend libraries (see the Gantt chart in `projects/show.html.erb`) rather than wiring up the unused `importmap-rails` pipeline.

**Tech Stack:** Rails 7.2.3, PostgreSQL, Action Text / Active Storage (framework, no new gem), Trix 2.1.6 via CDN, Minitest.

## Global Constraints

- No new Gemfile entries — `actiontext`/`activestorage` are already resolved (see `Gemfile.lock`) and loaded via `require "rails/all"` in `config/application.rb`.
- No `importmap-rails`/`app/javascript` wiring — load Trix via CDN `<link>`/`<script>` in `content_for :head`, matching the existing frappe-gantt CDN pattern in `app/views/projects/show.html.erb`.
- The one pre-existing `LogEntry` (id present in the pilot DB with `body: "Prueba"`) must survive the migration with its content intact.
- Out of scope: file/image attachments in notes, editing existing notes, WYSIWYG on any field other than `LogEntry#body`.

---

### Task 1: Action Text schema (ActiveStorage + Action Text tables, data migration)

**Files:**
- Create: `db/migrate/<timestamp>_create_active_storage_tables.rb`
- Create: `db/migrate/<timestamp+1>_create_action_text_tables.rb`
- Create: `db/migrate/<timestamp+2>_migrate_log_entry_body_to_action_text.rb`

**Interfaces:**
- Produces: `active_storage_blobs`, `active_storage_attachments`, `active_storage_variant_records`, `action_text_rich_texts` tables; `log_entries.body` column removed. Task 2 depends on `action_text_rich_texts` existing and `log_entries.body` being gone (that's what makes `has_rich_text :body` correct instead of colliding with a leftover column).

- [ ] **Step 1: Record the pre-existing pilot note for later verification**

```bash
bin/rails runner 'LogEntry.all.each { |e| puts "id=#{e.id} body=#{e.body.inspect}" }'
```
Expected output: `id=1 body="Prueba"` (or similar — note whatever id/body you see, you'll verify it survived the migration in Step 5).

- [ ] **Step 2: Create the ActiveStorage tables migration**

```bash
bin/rails generate migration CreateActiveStorageTables
```

Replace the generated file's contents with:

```ruby
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

- [ ] **Step 3: Create the Action Text table migration**

```bash
bin/rails generate migration CreateActionTextTables
```

Replace the generated file's contents with:

```ruby
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

- [ ] **Step 4: Create the data migration (backfill + drop old column)**

```bash
bin/rails generate migration MigrateLogEntryBodyToActionText
```

Replace the generated file's contents with:

```ruby
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

This must run BEFORE Task 2 changes `app/models/log_entry.rb` to `has_rich_text :body` — it operates on the table via raw SQL precisely so it doesn't depend on the model's Ruby-level definition matching the schema mid-migration.

- [ ] **Step 5: Run migrations on dev and test, verify the pilot note survived**

```bash
bin/rails db:migrate
RAILS_ENV=test bin/rails db:migrate
```
Expected: all 3 migrations run, no errors.

```bash
bin/rails runner 'r = ActionText::RichText.find_by(record_type: "LogEntry", record_id: 1, name: "body"); puts r.body.to_s'
```
Expected output includes `Prueba` (or whatever body you recorded in Step 1), wrapped in a `<div>`.

```bash
bin/rails runner 'puts LogEntry.column_names.inspect'
```
Expected: `log_entries` no longer has a `body` column (the `column_names` output should NOT include `"body"`).

- [ ] **Step 6: Run the full test suite to confirm nothing else broke yet**

```bash
bin/rails test
```
Expected: failures in `test/models/log_entry_test.rb` and `test/controllers/log_entries_controller_test.rb` and possibly `test/controllers/projects_controller_test.rb` — this is EXPECTED at this point, since `LogEntry` doesn't have `has_rich_text :body` yet (Task 2) and the view still uses `f.text_area :body` (Task 3) against a column that no longer exists. Confirm the failures are about the missing `body` column/method, not something unrelated — if you see unrelated failures, stop and report BLOCKED.

- [ ] **Step 7: Commit**

```bash
git add db/migrate db/schema.rb
git commit -m "Add Action Text schema and migrate LogEntry body off the old text column"
```

---

### Task 2: `has_rich_text :body` on `LogEntry`

**Files:**
- Modify: `app/models/log_entry.rb`
- Test: `test/models/log_entry_test.rb`

**Interfaces:**
- Consumes: `action_text_rich_texts` table (Task 1).
- Produces: `LogEntry#body` as an `ActionText::RichText`-backed attribute (assignable with a plain string or HTML, readable via `#to_s`/`#to_plain_text`). Task 3's view and Task 1's already-broken tests both depend on this.

- [ ] **Step 1: Update the model**

Read `app/models/log_entry.rb` first (it's small, already shown below for reference). Add `has_rich_text :body`:

```ruby
class LogEntry < ApplicationRecord
  belongs_to :project
  belongs_to :user
  belongs_to :log_entry_type

  has_rich_text :body

  validates :body, presence: true
end
```

- [ ] **Step 2: Run the two existing model tests to confirm they pass again**

```bash
bin/rails test test/models/log_entry_test.rb
```
Expected: PASS (2 tests) — `has_rich_text` makes `body:` assignable and `.valid?`/`.invalid?` behave the same as the old text column for presence.

- [ ] **Step 3: Write a new failing test for actual rich-text round-tripping**

Add to `test/models/log_entry_test.rb`:

```ruby
test "body persists rich text formatting" do
  entry = LogEntry.create!(
    project: @project,
    user: users(:juan),
    log_entry_type: log_entry_types(:nota),
    body: "<strong>Urgente</strong>: revisar instalación"
  )

  entry.reload
  assert_includes entry.body.to_s, "<strong>Urgente</strong>"
end
```

- [ ] **Step 4: Run it to verify it currently passes (this confirms `has_rich_text` is wired correctly — Action Text sanitizes but preserves safe tags like `<strong>`)**

```bash
bin/rails test test/models/log_entry_test.rb -n test_body_persists_rich_text_formatting
```
Expected: PASS. If it fails because `<strong>` was stripped, Action Text's default sanitizer is misconfigured for this Rails version — stop and report BLOCKED with the actual output, don't work around it.

- [ ] **Step 5: Run the full test suite**

```bash
bin/rails test
```
Expected: `test/models/log_entry_test.rb` and `test/controllers/log_entries_controller_test.rb` now pass. `test/controllers/projects_controller_test.rb`'s bitácora test may still fail — that depends on Task 3's view change (the form still references `f.text_area :body`, which now points at a `has_rich_text` attribute Rails' `text_area` helper doesn't understand the same way). If the projects controller test still fails at this point, that's expected — Task 3 fixes it.

- [ ] **Step 6: Commit**

```bash
git add app/models/log_entry.rb test/models/log_entry_test.rb
git commit -m "Add has_rich_text :body to LogEntry"
```

---

### Task 3: Trix editor in the bitácora form

**Files:**
- Modify: `app/views/projects/show.html.erb`
- Test: `test/controllers/projects_controller_test.rb` (existing test, verify/adjust)

**Interfaces:**
- Consumes: `LogEntry#body` as a `has_rich_text` attribute (Task 2), `f.rich_text_area` (Rails/Action Text view helper).

- [ ] **Step 1: Read the current view**

Read `app/views/projects/show.html.erb` in full — locate the `content_for :head` block (currently loads frappe-gantt's CSS) and the bitácora form (`form_with model: LogEntry.new, url: project_log_entries_path(@project)`).

- [ ] **Step 2: Add Trix CDN assets to `content_for :head`**

Change:
```erb
<% content_for :head do %>
  <link href="https://cdn.jsdelivr.net/npm/frappe-gantt@1.2.2/dist/frappe-gantt.css" rel="stylesheet">
<% end %>
```
to:
```erb
<% content_for :head do %>
  <link href="https://cdn.jsdelivr.net/npm/frappe-gantt@1.2.2/dist/frappe-gantt.css" rel="stylesheet">
  <link href="https://cdn.jsdelivr.net/npm/trix@2.1.6/dist/trix.css" rel="stylesheet">
  <script src="https://cdn.jsdelivr.net/npm/trix@2.1.6/dist/trix.umd.min.js"></script>
<% end %>
```

- [ ] **Step 3: Replace the textarea with a rich text area**

Find, inside the bitácora form:
```erb
<%= f.text_area :body, class: "form-control form-control-sm", rows: 1, placeholder: "Agregar nota..." %>
```
Replace with:
```erb
<%= f.rich_text_area :body, class: "trix-content mb-0" %>
```
(No `rows`/`form-control-sm` — those are native-`<textarea>` Bootstrap classes; Trix ships its own toolbar/editor box styling via `trix.css`.)

- [ ] **Step 4: Run the projects controller test to check the bitácora rendering test**

```bash
bin/rails test test/controllers/projects_controller_test.rb -n test_show_renders_the_bitácora_with_existing_entries_and_an_add_form
```
Expected: PASS. If it fails because the test asserts on the old `text_area`'s specific markup (`form[action=?]` should still match since the `form_with` tag itself didn't change — only the field inside it did), read the failure and fix only if the assertion was checking something now-obsolete about the textarea specifically; don't weaken the assertion's intent.

- [ ] **Step 5: Run the full test suite**

```bash
bin/rails test
```
Expected: PASS, 0 failures, 0 errors — this is the last task, everything should be green now.

- [ ] **Step 6: Commit**

```bash
git add app/views/projects/show.html.erb
git commit -m "Use a Trix rich text editor for bitácora notes"
```

---

## Post-Plan Manual Verification

- [ ] Start the app, open a project's show page, confirm the Trix toolbar (bold/italic/lists/link buttons) renders in place of the old plain textarea.
- [ ] Add a note with bold text and a link, submit, confirm it renders formatted (not as raw HTML text) in the entry list below.
- [ ] Confirm the pre-existing "Prueba" note (or whatever pilot data exists) still displays correctly after the migration.
- [ ] Confirm deleting your own note and being blocked from deleting someone else's note still works as before (unrelated to this change, but touches the same card — quick regression check).
