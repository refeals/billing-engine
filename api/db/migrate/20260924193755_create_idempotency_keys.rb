class CreateIdempotencyKeys < ActiveRecord::Migration[8.1]
  def change
    create_table :idempotency_keys do |t|
      t.string :key, null: false
      t.string :request_fingerprint, null: false
      # Both null while the first request is still running.
      t.integer :response_status
      t.text :response_body
      t.timestamps
    end

    add_index :idempotency_keys, :key, unique: true
  end
end
