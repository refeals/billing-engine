class AddScenarioRunToMockedWebhookEvents < ActiveRecord::Migration[8.1]
  def change
    # Which scenario made the provider emit this event, so the Scenario Lab can show exactly
    # the events a run produced.
    add_column :mocked_webhook_events, :scenario_run_id, :integer
    add_index :mocked_webhook_events, :scenario_run_id
  end
end
