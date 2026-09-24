class CreateInvoices < ActiveRecord::Migration[8.1]
  STATUSES = %w[open paid void uncollectible].freeze
  BILLING_REASONS = %w[subscription_create subscription_cycle subscription_update manual].freeze

  def change
    create_table :invoices do |t|
      t.references :subscription, null: false, foreign_key: true
      t.references :customer, null: false, foreign_key: true
      t.string :provider_invoice_id, null: false
      t.string :number, null: false
      t.string :status, null: false
      t.string :billing_reason, null: false
      t.datetime :period_start, null: false
      t.datetime :period_end, null: false
      t.integer :subtotal_cents, null: false
      t.integer :credit_applied_cents, null: false, default: 0
      t.integer :total_cents, null: false
      t.integer :amount_paid_cents, null: false, default: 0
      t.integer :amount_refunded_cents, null: false, default: 0
      t.integer :amount_due_cents, null: false
      t.string :currency, null: false, default: "USD"
      t.datetime :issued_at, null: false
      t.datetime :paid_at
      t.integer :attempt_count, null: false, default: 0
      t.datetime :last_provider_event_at
      t.timestamps
    end

    add_index :invoices, :provider_invoice_id, unique: true
    add_index :invoices, :number, unique: true
    add_index :invoices, :status
    add_check_constraint :invoices, "status IN (#{quoted(STATUSES)})", name: "invoices_status_known"
    add_check_constraint :invoices, "billing_reason IN (#{quoted(BILLING_REASONS)})", name: "invoices_billing_reason_known"
    add_check_constraint :invoices,
      "subtotal_cents >= 0 AND credit_applied_cents >= 0 AND amount_paid_cents >= 0 AND amount_refunded_cents >= 0 AND amount_due_cents >= 0",
      name: "invoices_amounts_non_negative"
    # The arithmetic is guaranteed by the database, not only by the code that builds invoices.
    add_check_constraint :invoices, "total_cents = subtotal_cents - credit_applied_cents", name: "invoices_total_consistent"
  end

  private

  def quoted(values)
    values.map { |value| "'#{value}'" }.join(", ")
  end
end
