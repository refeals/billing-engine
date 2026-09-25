class CreateCustomerNotifications < ActiveRecord::Migration[8.1]
  def change
    # What would have been emailed to the customer. Nothing is sent; this is the outbox a
    # mailer would read from.
    create_table :customer_notifications do |t|
      t.references :customer, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :subject, null: false
      t.text :body, null: false
      t.integer :dunning_case_id
      t.integer :dunning_step_id
      t.datetime :sent_at, null: false
      t.datetime :created_at, null: false
    end

    create_append_only_triggers :customer_notifications
  end
end
