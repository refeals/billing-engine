class CreateBillingEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :billing_events do |t|
      # What the event is about. Many events concern records that are neither a
      # subscription nor a customer (plans, invoices, the clock).
      t.references :subject, polymorphic: true, index: true

      # Denormalized so the per-subscription and per-customer timelines are one indexed
      # query. Foreign keys arrive with their tables (plans 03, 04 and 05).
      t.integer :subscription_id
      t.integer :customer_id
      t.integer :webhook_event_id

      t.string :event_type, null: false
      t.string :actor_type, null: false
      t.json :data, null: false, default: {}

      # Business time (simulated clock) versus the real time the row was written.
      t.datetime :occurred_at, null: false
      t.datetime :created_at, null: false
    end

    add_index :billing_events, [ :subscription_id, :occurred_at ]
    add_index :billing_events, [ :customer_id, :occurred_at ]
    add_index :billing_events, :event_type
    add_index :billing_events, :occurred_at

    create_append_only_triggers :billing_events
  end
end
