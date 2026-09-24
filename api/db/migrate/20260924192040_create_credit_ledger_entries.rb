class CreateCreditLedgerEntries < ActiveRecord::Migration[8.1]
  REASONS = %w[downgrade_proration applied_to_invoice refund_to_balance manual_adjustment].freeze

  def change
    create_table :credit_ledger_entries do |t|
      t.references :customer, null: false, foreign_key: true, index: false
      t.integer :amount_cents, null: false
      # Running balance after this entry: makes the ledger readable on its own and gives
      # reconciliation a checkpoint per row.
      t.integer :balance_after_cents, null: false
      t.string :reason, null: false
      # Foreign keys arrive with their tables (plans 07 and 08).
      t.integer :invoice_id
      t.integer :plan_change_id
      t.string :note
      t.datetime :occurred_at, null: false
      t.datetime :created_at, null: false
    end

    add_index :credit_ledger_entries, [ :customer_id, :id ]
    add_check_constraint :credit_ledger_entries, "amount_cents <> 0", name: "credit_ledger_entries_amount_non_zero"
    add_check_constraint :credit_ledger_entries, "balance_after_cents >= 0", name: "credit_ledger_entries_balance_non_negative"
    add_check_constraint :credit_ledger_entries, "reason IN (#{REASONS.map { |reason| "'#{reason}'" }.join(', ')})",
      name: "credit_ledger_entries_reason_known"

    create_append_only_triggers :credit_ledger_entries
  end
end
