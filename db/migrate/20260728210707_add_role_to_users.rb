class AddRoleToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :role, :string, default: "visor", null: false

    reversible do |dir|
      dir.up { execute "UPDATE users SET role = 'admin' WHERE email = 'admin@nalakalu.com'" }
    end
  end
end
