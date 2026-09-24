# Rows of an append-only table are history: they are written once and never changed.
# This concern gives a clear Ruby error for the common paths; the database triggers
# (see Database::AppendOnlyTriggers) are what actually guarantee it, including for
# `update_all`, `delete_all` and raw SQL.
module AppendOnly
  extend ActiveSupport::Concern

  def readonly?
    persisted? || super
  end

  def destroy
    raise ActiveRecord::ReadOnlyRecord, "#{self.class.name} is append-only"
  end

  def delete
    raise ActiveRecord::ReadOnlyRecord, "#{self.class.name} is append-only"
  end
end
