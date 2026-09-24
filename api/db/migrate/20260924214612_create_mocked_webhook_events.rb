class CreateMockedWebhookEvents < ActiveRecord::Migration[8.1]
  def change
    # The fake provider's outbox: every event it ever emitted, delivered or not. It is the
    # provider's own record, independent from the engine's inbox (webhook_events), which is
    # what makes it a trustworthy "expected" source for reconciliation.
    create_table :mocked_webhook_events do |t|
      t.string :event_id, null: false
      t.string :event_type, null: false
      t.string :api_version, null: false
      t.json :payload, null: false
      t.string :provider_object_id, null: false
      t.string :provider_subscription_id
      t.datetime :provider_created_at, null: false
      t.string :delivery_mode, null: false, default: "deliver"
      t.integer :copies, null: false, default: 1
      t.string :delivery_status, null: false, default: "pending"
      t.integer :delivery_count, null: false, default: 0
      t.integer :delivery_attempts, null: false, default: 0
      t.string :last_delivery_result
      t.datetime :last_delivered_at
      t.timestamps
    end

    add_index :mocked_webhook_events, :event_id, unique: true
    add_index :mocked_webhook_events, :provider_subscription_id
    add_index :mocked_webhook_events, :delivery_status
    add_check_constraint :mocked_webhook_events, "delivery_status IN ('pending', 'delivered', 'dropped')",
      name: "mocked_webhook_events_delivery_status_known"
    add_check_constraint :mocked_webhook_events, "delivery_mode IN ('deliver', 'drop')",
      name: "mocked_webhook_events_delivery_mode_known"
    add_check_constraint :mocked_webhook_events, "copies BETWEEN 1 AND 5", name: "mocked_webhook_events_copies_range"
  end
end
