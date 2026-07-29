class CreateResponsibles < ActiveRecord::Migration[7.2]
  def change
    create_table :responsibles do |t|
      t.string :name, null: false
      t.string :color, default: "#6c757d", null: false
      t.references :user, null: true, foreign_key: true, index: { unique: true }
      t.timestamps
    end
  end
end
