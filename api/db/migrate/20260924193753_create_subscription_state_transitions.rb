class CreateSubscriptionStateTransitions < ActiveRecord::Migration[8.1]
  def change
    create_table :subscription_state_transitions do |t|
      t.references :subscription, null: false, foreign_key: true, index: false
      t.string :from_status
      t.string :to_status, null: false
      t.string :reason, null: false
      t.string :actor_type, null: false
      t.integer :webhook_event_id
      # The audit event written in the same transaction as this transition.
      t.references :billing_event, null: false, foreign_key: true, index: false
      t.json :metadata, null: false, default: {}
      t.datetime :occurred_at, null: false
      t.datetime :created_at, null: false
    end

    add_index :subscription_state_transitions, [ :subscription_id, :occurred_at ]

    create_append_only_triggers :subscription_state_transitions
  end
end
