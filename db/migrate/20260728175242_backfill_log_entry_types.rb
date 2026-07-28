class BackfillLogEntryTypes < ActiveRecord::Migration[7.2]
  def up
    ProjectType.find_each do |project_type|
      next if project_type.log_entry_types.exists?

      %w[Nota Incidencia Cambio].each { |name| project_type.log_entry_types.create!(name: name) }
    end
  end

  def down
    # ponytail: no-op — don't destroy bitácora types that may already have entries attached.
  end
end
