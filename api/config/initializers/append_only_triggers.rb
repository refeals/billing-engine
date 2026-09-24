require Rails.root.join("lib/database/append_only_triggers").to_s

ActiveSupport.on_load(:active_record) do
  ActiveRecord::Migration.include(Database::AppendOnlyTriggers)
end
