# One row per sign-in. The browser only holds a signed cookie with the row's id, so signing
# out (deleting the row) ends the session on the server, not just in the browser.
class CreateSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :ip_address
      t.string :user_agent
      t.datetime :last_seen_at, null: false
      t.timestamps
    end
  end
end
