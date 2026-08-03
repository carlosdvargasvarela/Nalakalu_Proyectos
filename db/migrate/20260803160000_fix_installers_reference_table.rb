class FixInstallersReferenceTable < ActiveRecord::Migration[7.2]
  def up
    execute "UPDATE field_definitions SET reference_table = 'responsibles' WHERE reference_table = 'installers'"
  end

  def down
    execute "UPDATE field_definitions SET reference_table = 'installers' WHERE reference_table = 'responsibles' AND key = 'instalador'"
  end
end
