class ChangeDurationReferenceFieldDefinitionForeignKeyToNullify < ActiveRecord::Migration[7.2]
  def change
    remove_foreign_key :project_types, :field_definitions, column: :duration_reference_field_definition_id
    add_foreign_key :project_types, :field_definitions, column: :duration_reference_field_definition_id, on_delete: :nullify
  end
end
