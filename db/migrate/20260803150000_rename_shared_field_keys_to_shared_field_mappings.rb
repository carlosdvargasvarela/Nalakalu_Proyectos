class RenameSharedFieldKeysToSharedFieldMappings < ActiveRecord::Migration[7.2]
  def up
    rename_column :project_type_associations, :shared_field_keys, :shared_field_mappings
    execute <<~SQL
      UPDATE project_type_associations
      SET shared_field_mappings = (
        SELECT jsonb_agg(jsonb_build_object('from', key, 'to', key))
        FROM jsonb_array_elements_text(shared_field_mappings) AS key
      )
      WHERE jsonb_array_length(shared_field_mappings) > 0
    SQL
  end

  def down
    execute <<~SQL
      UPDATE project_type_associations
      SET shared_field_mappings = (
        SELECT jsonb_agg(mapping->>'from')
        FROM jsonb_array_elements(shared_field_mappings) AS mapping
      )
      WHERE jsonb_array_length(shared_field_mappings) > 0
    SQL
    rename_column :project_type_associations, :shared_field_mappings, :shared_field_keys
  end
end
