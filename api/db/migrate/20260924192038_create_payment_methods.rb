class CreatePaymentMethods < ActiveRecord::Migration[8.1]
  def change
    create_table :payment_methods do |t|
      t.references :customer, null: false, foreign_key: true, index: true
      t.string :provider_payment_method_id, null: false
      # Stripe test-mode token (e.g. pm_card_chargeDeclined). It decides how the fake
      # provider answers a charge, the same way test cards work in Stripe.
      t.string :test_card_token, null: false
      t.string :brand, null: false
      t.string :last4, null: false
      t.integer :exp_month, null: false
      t.integer :exp_year, null: false
      t.boolean :is_default, null: false, default: false
      t.timestamps
    end

    add_index :payment_methods, :provider_payment_method_id, unique: true
    # At most one default card per customer, guaranteed by the database.
    add_index :payment_methods, :customer_id, unique: true, where: "is_default = 1",
      name: "index_payment_methods_one_default_per_customer"
    add_check_constraint :payment_methods, "exp_month BETWEEN 1 AND 12", name: "payment_methods_exp_month_valid"
  end
end
