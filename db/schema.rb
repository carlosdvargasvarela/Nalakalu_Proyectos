# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.2].define(version: 2026_07_29_005708) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "action_text_rich_texts", force: :cascade do |t|
    t.string "name", null: false
    t.text "body"
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["record_type", "record_id", "name"], name: "index_action_text_rich_texts_uniqueness", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "field_definitions", force: :cascade do |t|
    t.bigint "project_type_id", null: false
    t.string "key", null: false
    t.string "label", null: false
    t.string "data_type", null: false
    t.string "reference_table"
    t.integer "position", default: 0, null: false
    t.boolean "show_in_gantt", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["project_type_id", "key"], name: "index_field_definitions_on_project_type_id_and_key", unique: true
    t.index ["project_type_id"], name: "index_field_definitions_on_project_type_id"
  end

  create_table "installers", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "color", default: "#6c757d", null: false
  end

  create_table "log_entries", force: :cascade do |t|
    t.bigint "project_id", null: false
    t.bigint "user_id", null: false
    t.bigint "log_entry_type_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["log_entry_type_id"], name: "index_log_entries_on_log_entry_type_id"
    t.index ["project_id"], name: "index_log_entries_on_project_id"
    t.index ["user_id"], name: "index_log_entries_on_user_id"
  end

  create_table "log_entry_types", force: :cascade do |t|
    t.bigint "project_type_id", null: false
    t.string "name", null: false
    t.string "color", default: "#6c757d", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["project_type_id"], name: "index_log_entry_types_on_project_type_id"
  end

  create_table "project_accesses", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "project_id", null: false
    t.boolean "can_edit", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id"], name: "index_project_accesses_on_project_id"
    t.index ["user_id", "project_id"], name: "index_project_accesses_on_user_id_and_project_id", unique: true
    t.index ["user_id"], name: "index_project_accesses_on_user_id"
  end

  create_table "project_stages", force: :cascade do |t|
    t.bigint "project_id", null: false
    t.bigint "stage_template_id"
    t.string "name", null: false
    t.date "start_date"
    t.date "end_date"
    t.integer "progress_percent", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["project_id"], name: "index_project_stages_on_project_id"
    t.index ["stage_template_id"], name: "index_project_stages_on_stage_template_id"
    t.index ["user_id"], name: "index_project_stages_on_user_id"
  end

  create_table "project_type_accesses", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "project_type_id", null: false
    t.boolean "can_edit", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["project_type_id"], name: "index_project_type_accesses_on_project_type_id"
    t.index ["user_id", "project_type_id"], name: "index_project_type_accesses_on_user_id_and_project_type_id", unique: true
    t.index ["user_id"], name: "index_project_type_accesses_on_user_id"
  end

  create_table "project_types", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_project_types_on_slug", unique: true
  end

  create_table "projects", force: :cascade do |t|
    t.bigint "project_type_id", null: false
    t.string "name", null: false
    t.jsonb "custom_fields", default: {}, null: false
    t.string "status", default: "active", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["project_type_id"], name: "index_projects_on_project_type_id"
  end

  create_table "stage_templates", force: :cascade do |t|
    t.bigint "project_type_id", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "color", default: "#6c757d", null: false
    t.boolean "default_in_filter", default: false, null: false
    t.index ["project_type_id"], name: "index_stage_templates_on_project_type_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "role", default: "visor", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "versions", force: :cascade do |t|
    t.string "whodunnit"
    t.datetime "created_at"
    t.bigint "item_id", null: false
    t.string "item_type", null: false
    t.string "event", null: false
    t.text "object"
    t.text "object_changes"
    t.index ["item_type", "item_id"], name: "index_versions_on_item_type_and_item_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "field_definitions", "project_types"
  add_foreign_key "log_entries", "log_entry_types"
  add_foreign_key "log_entries", "projects"
  add_foreign_key "log_entries", "users"
  add_foreign_key "log_entry_types", "project_types"
  add_foreign_key "project_accesses", "projects"
  add_foreign_key "project_accesses", "users"
  add_foreign_key "project_stages", "projects"
  add_foreign_key "project_stages", "stage_templates", on_delete: :nullify
  add_foreign_key "project_stages", "users"
  add_foreign_key "project_type_accesses", "project_types"
  add_foreign_key "project_type_accesses", "users"
  add_foreign_key "projects", "project_types"
  add_foreign_key "stage_templates", "project_types"
end
