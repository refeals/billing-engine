class CreateRefunds < ActiveRecord::Migration[8.1]
  def change
    create_table :refunds do |t|
      t.references :invoice, null: false, foreign_key: true
      t.references :payment_attempt, foreign_key: true, index: false
      # Null for refunds to the credit balance: no money leaves, so the provider isn't involved.
      t.string :provider_refund_id
      t.integer :amount_cents, null: false
      t.string :destination, null: false
      t.string :reason, null: false
      t.string :status, null: false
      t.string :failure_reason
      t.datetime :requested_at, null: false
      t.datetime :completed_at
      t.datetime :last_provider_event_at
      t.timestamps
    end

    add_index :refunds, :provider_refund_id, unique: true
    add_check_constraint :refunds, "amount_cents > 0", name: "refunds_amount_positive"
    add_check_constraint :refunds, "destination IN ('original_method', 'credit_balance')", name: "refunds_destination_known"
    add_check_constraint :refunds, "reason IN ('requested_by_customer', 'duplicate', 'fraudulent', 'service_issue')",
      name: "refunds_reason_known"
    add_check_constraint :refunds, "status IN ('pending', 'succeeded', 'failed')", name: "refunds_status_known"
  end
end
