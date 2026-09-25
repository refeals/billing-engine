class CreateDunningCases < ActiveRecord::Migration[8.1]
  STEPS = %w[day_0_notice day_3_retry day_7_suspend day_14_cancel].freeze

  def change
    create_table :dunning_cases do |t|
      t.references :subscription, null: false, foreign_key: true, index: false
      t.references :invoice, null: false, foreign_key: true, index: false
      t.string :status, null: false, default: "open"
      t.datetime :started_at, null: false
      t.string :last_step
      t.string :next_step
      t.datetime :next_step_at
      t.datetime :closed_at
      t.string :closed_reason
      t.timestamps
    end

    # One open case per unpaid invoice and per subscription: a second failure on the same
    # invoice (the day-3 retry, a manual retry) continues the case instead of starting over.
    add_index :dunning_cases, :invoice_id, unique: true, where: "status = 'open'", name: "index_dunning_cases_one_open_per_invoice"
    add_index :dunning_cases, :subscription_id, unique: true, where: "status = 'open'",
      name: "index_dunning_cases_one_open_per_subscription"
    add_index :dunning_cases, :subscription_id
    add_index :dunning_cases, :next_step_at
    add_check_constraint :dunning_cases, "status IN ('open', 'recovered', 'exhausted', 'canceled')", name: "dunning_cases_status_known"
  end
end
