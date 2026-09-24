class CreateCustomers < ActiveRecord::Migration[8.1]
  def change
    create_table :customers do |t|
      t.string :name, null: false
      t.string :email, null: false
      t.string :provider_customer_id, null: false
      # Cache of the credit ledger sum; the ledger is the source of truth.
      t.integer :credit_balance_cents, null: false, default: 0
      t.timestamps
    end

    add_index :customers, :email, unique: true
    add_index :customers, :provider_customer_id, unique: true
    add_check_constraint :customers, "credit_balance_cents >= 0", name: "customers_credit_balance_non_negative"
  end
end
