module Demo
  # Wipes the whole database and seeds it again. This is the one path that deletes audit
  # history, and it only exists for the demo: it deletes everything, not selected rows.
  # Append-only tables refuse DELETE through triggers, so the triggers are dropped for the
  # duration of the transaction and recreated from their own recorded SQL.
  class Reset < ApplicationService
    KEEP = %w[schema_migrations ar_internal_metadata].freeze

    # `reseed: false` only wipes (used by the seed specs to clean up after themselves).
    def initialize(reseed: true)
      @reseed = reseed
    end

    def call
      connection = ActiveRecord::Base.lease_connection
      triggers = connection.select_rows("SELECT name, sql FROM sqlite_master WHERE type = 'trigger'")

      ActiveRecord::Base.transaction do
        # Rows reference each other; checking foreign keys at commit (when everything is gone)
        # instead of per statement lets the tables be emptied in any order.
        connection.execute("PRAGMA defer_foreign_keys = ON")
        triggers.each { |name, _| connection.execute("DROP TRIGGER #{connection.quote_table_name(name)}") }
        (connection.tables - KEEP).each { |table| connection.execute("DELETE FROM #{connection.quote_table_name(table)}") }
        # AUTOINCREMENT counters restart too, so a fresh demo starts at id 1.
        if connection.select_value("SELECT 1 FROM sqlite_master WHERE name = 'sqlite_sequence'")
          connection.execute("DELETE FROM sqlite_sequence")
        end
        triggers.each { |_, sql| connection.execute(sql) }
      end

      # Nothing else is read after a bare wipe: even reading the clock would recreate it.
      Seed.call if @reseed
    end
  end
end
