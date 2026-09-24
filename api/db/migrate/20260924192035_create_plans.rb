class CreatePlans < ActiveRecord::Migration[8.1]
  def change
    create_table :plans do |t|
      t.string :code, null: false
      t.string :name, null: false
      t.integer :amount_cents, null: false
      t.string :currency, null: false, default: "USD"
      t.string :interval, null: false
      t.integer :trial_days, null: false, default: 0
      t.datetime :archived_at
      t.timestamps
    end

    add_index :plans, :code, unique: true
    add_check_constraint :plans, "amount_cents > 0", name: "plans_amount_positive"
    add_check_constraint :plans, "interval IN ('month', 'year')", name: "plans_interval_known"
    add_check_constraint :plans, "currency = 'USD'", name: "plans_currency_usd"
    add_check_constraint :plans, "trial_days >= 0", name: "plans_trial_days_non_negative"
  end
end
