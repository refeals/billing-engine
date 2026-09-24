class CreateWebhookEvents < ActiveRecord::Migration[8.1]
  STATUSES = %w[received processed failed skipped_stale ignored_unhandled].freeze

  def change
    # The inbox: one row per provider event, whatever happens to it. Not append-only, since
    # it is also the work queue (status, attempts, last error change as it is processed).
    create_table :webhook_events do |t|
      t.string :provider_event_id, null: false
      t.string :event_type, null: false
      t.string :provider_object_id, null: false
      t.json :payload, null: false
      t.datetime :provider_created_at, null: false
      # Simulated time, so the inbox lines up with the rest of the timeline.
      t.datetime :received_at, null: false
      t.string :processing_status, null: false, default: "received"
      t.datetime :processed_at
      t.integer :attempts, null: false, default: 0
      t.text :last_error
      t.integer :duplicate_deliveries_count, null: false, default: 0
      t.timestamps
    end

    # The idempotency guarantee: the same provider event can only ever have one row.
    add_index :webhook_events, :provider_event_id, unique: true
    add_index :webhook_events, :provider_object_id
    add_index :webhook_events, :processing_status
    add_index :webhook_events, :event_type
    add_check_constraint :webhook_events, "processing_status IN (#{STATUSES.map { |status| "'#{status}'" }.join(', ')})",
      name: "webhook_events_processing_status_known"
  end
end
