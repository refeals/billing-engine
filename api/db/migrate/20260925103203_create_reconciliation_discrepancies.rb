class CreateReconciliationDiscrepancies < ActiveRecord::Migration[8.1]
  KINDS = %w[status_mismatch plan_mismatch period_mismatch missing_invoice invoice_status_mismatch
    invoice_amount_mismatch undelivered_event failed_event].freeze

  def change
    create_table :reconciliation_discrepancies do |t|
      t.references :first_run, null: false, foreign_key: { to_table: :reconciliation_runs }, index: false
      t.references :last_seen_run, null: false, foreign_key: { to_table: :reconciliation_runs }, index: false
      t.references :subscription, null: false, foreign_key: true
      t.string :kind, null: false
      # What the difference is about (an invoice, an event, a field), so the same problem
      # found by the next run is recognized instead of reported twice.
      t.string :subject_key, null: false
      t.string :field
      t.string :internal_value
      t.string :expected_value
      t.json :evidence_event_ids, null: false, default: []
      t.string :status, null: false, default: "open"
      t.string :resolution
      t.text :resolution_note
      t.datetime :resolved_at
      t.timestamps
    end

    add_index :reconciliation_discrepancies, [ :subscription_id, :kind, :subject_key ], unique: true,
      where: "status = 'open'", name: "index_reconciliation_discrepancies_one_open_per_subject"
    add_index :reconciliation_discrepancies, :status
    add_check_constraint :reconciliation_discrepancies, "kind IN (#{KINDS.map { |kind| "'#{kind}'" }.join(', ')})",
      name: "reconciliation_discrepancies_kind_known"
    add_check_constraint :reconciliation_discrepancies, "status IN ('open', 'resolved', 'acknowledged', 'cleared')",
      name: "reconciliation_discrepancies_status_known"
  end
end
