module Database
  # Migration helper that makes a table append-only at the database level. Model
  # callbacks can be skipped (`update_column`, `update_all`, raw SQL); a trigger can't.
  module AppendOnlyTriggers
    def create_append_only_triggers(table)
      reversible do |direction|
        direction.up do
          %w[update delete].each do |operation|
            execute <<~SQL
              CREATE TRIGGER #{table}_no_#{operation}
              BEFORE #{operation.upcase} ON #{table}
              BEGIN
                SELECT RAISE(ABORT, '#{table} is append-only');
              END;
            SQL
          end
        end

        direction.down do
          %w[update delete].each { |operation| execute "DROP TRIGGER IF EXISTS #{table}_no_#{operation};" }
        end
      end
    end
  end
end
