class CreatePlanChanges < ActiveRecord::Migration[8.1]
  def change
    create_table :plan_changes do |t|
      t.references :subscription, null: false, foreign_key: true
      t.references :from_plan, null: false, foreign_key: { to_table: :plans }, index: false
      t.references :to_plan, null: false, foreign_key: { to_table: :plans }, index: false
      t.string :kind, null: false
      t.string :strategy, null: false
      t.string :status, null: false
      # The instant the proration was computed for; null for changes that wait for renewal.
      t.datetime :proration_date
      t.datetime :effective_at, null: false
      t.integer :credit_cents, null: false, default: 0
      t.integer :charge_cents, null: false, default: 0
      t.integer :net_cents, null: false, default: 0
      t.references :invoice, foreign_key: true, index: false
      t.timestamps
    end

    # At most one change waiting for renewal per subscription, guaranteed by the database.
    add_index :plan_changes, :subscription_id, unique: true, where: "status = 'scheduled'",
      name: "index_plan_changes_one_scheduled_per_subscription"
    add_check_constraint :plan_changes, "kind IN ('upgrade', 'downgrade', 'lateral', 'trial_swap')", name: "plan_changes_kind_known"
    add_check_constraint :plan_changes, "strategy IN ('immediate', 'at_period_end')", name: "plan_changes_strategy_known"
    add_check_constraint :plan_changes, "status IN ('scheduled', 'applied', 'canceled')", name: "plan_changes_status_known"
    add_check_constraint :plan_changes, "net_cents = credit_cents + charge_cents", name: "plan_changes_net_consistent"
  end
end
