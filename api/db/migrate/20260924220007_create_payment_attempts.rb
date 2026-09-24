class CreatePaymentAttempts < ActiveRecord::Migration[8.1]
  def change
    create_table :payment_attempts do |t|
      t.references :invoice, null: false, foreign_key: true
      t.references :payment_method, foreign_key: true
      t.string :provider_charge_id, null: false
      t.string :status, null: false
      t.string :failure_code
      t.integer :amount_cents, null: false
      t.datetime :attempted_at, null: false
      t.integer :webhook_event_id
      t.datetime :created_at, null: false
    end

    # Two different events describing the same charge (charge.failed and
    # invoice.payment_failed) can't record it twice.
    add_index :payment_attempts, :provider_charge_id, unique: true
    add_check_constraint :payment_attempts, "status IN ('succeeded', 'failed')", name: "payment_attempts_status_known"

    create_append_only_triggers :payment_attempts
  end
end
