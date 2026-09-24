class CreateSubscriptions < ActiveRecord::Migration[8.1]
  STATUSES = %w[trialing active past_due paused canceled].freeze

  def change
    create_table :subscriptions do |t|
      t.references :customer, null: false, foreign_key: true, index: false
      t.references :plan, null: false, foreign_key: true
      t.string :provider_subscription_id, null: false
      t.string :status, null: false
      t.datetime :current_period_start, null: false
      t.datetime :current_period_end, null: false
      t.datetime :trial_ends_at
      t.boolean :cancel_at_period_end, null: false, default: false
      t.datetime :canceled_at
      t.string :cancellation_reason
      t.datetime :paused_at
      t.datetime :resumes_at
      t.datetime :access_suspended_at
      # Newest provider event applied to this subscription; older ones arriving late are
      # skipped (plan 05).
      t.datetime :last_provider_event_at
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end

    add_index :subscriptions, :provider_subscription_id, unique: true
    add_index :subscriptions, :status
    add_index :subscriptions, :current_period_end
    add_index :subscriptions, :customer_id
    # One live subscription per customer, guaranteed by the database. Canceled ones are
    # history and don't count.
    add_index :subscriptions, :customer_id, unique: true, where: "status <> 'canceled'",
      name: "index_subscriptions_one_live_per_customer"
    add_check_constraint :subscriptions, "status IN (#{STATUSES.map { |status| "'#{status}'" }.join(', ')})",
      name: "subscriptions_status_known"
  end
end
