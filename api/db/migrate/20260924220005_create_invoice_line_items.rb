class CreateInvoiceLineItems < ActiveRecord::Migration[8.1]
  KINDS = %w[subscription proration_credit proration_charge credit_applied].freeze

  def change
    create_table :invoice_line_items do |t|
      t.references :invoice, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :description, null: false
      t.references :plan, foreign_key: true, index: false
      # Negative for credits.
      t.integer :amount_cents, null: false
      t.datetime :period_start
      t.datetime :period_end
      t.datetime :created_at, null: false
    end

    add_check_constraint :invoice_line_items, "kind IN (#{KINDS.map { |kind| "'#{kind}'" }.join(', ')})",
      name: "invoice_line_items_kind_known"

    # An issued invoice is a document: its lines never change. Corrections are new documents.
    create_append_only_triggers :invoice_line_items
  end
end
