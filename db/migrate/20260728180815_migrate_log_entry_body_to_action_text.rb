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
