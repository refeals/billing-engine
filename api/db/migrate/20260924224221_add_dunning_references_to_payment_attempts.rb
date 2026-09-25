class AddDunningReferencesToPaymentAttempts < ActiveRecord::Migration[8.1]
  # Plain nullable columns: SQLite adds them with ALTER TABLE ADD COLUMN, without rebuilding
  # the table, so payment_attempts keeps its append-only triggers. A foreign key would force
  # a rebuild and drop them.
  def change
    add_column :payment_attempts, :dunning_case_id, :integer
    add_column :payment_attempts, :dunning_step_id, :integer
  end
end
