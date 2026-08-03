class AddSharedFieldKeysToProjectTypeAssociations < ActiveRecord::Migration[7.2]
  def change
    add_column :project_type_associations, :shared_field_keys, :jsonb, default: [], null: false
  end
end
