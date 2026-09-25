class CreateReconciliationRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :reconciliation_runs do |t|
      t.string :triggered_by, null: false
      # Null for a run over every subscription.
      t.references :scope_subscription, foreign_key: { to_table: :subscriptions }, index: false
      t.datetime :started_at, null: false
      t.datetime :finished_at
      t.integer :subscriptions_checked, null: false, default: 0
      t.integer :discrepancies_found, null: false, default: 0
      t.integer :discrepancies_opened, null: false, default: 0
      t.integer :discrepancies_cleared, null: false, default: 0
      t.timestamps
    end
  end
end
