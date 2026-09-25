class CreateScenarioRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :scenario_runs do |t|
      t.string :scenario_key, null: false
      t.string :status, null: false, default: "running"
      t.references :customer, foreign_key: true, index: false
      t.references :subscription, foreign_key: true, index: false
      # One entry per step, with the simulated time it ran at.
      t.json :log, null: false, default: []
      t.text :error
      t.datetime :started_at, null: false
      t.datetime :finished_at
      t.timestamps
    end

    add_index :scenario_runs, :scenario_key
    add_check_constraint :scenario_runs, "status IN ('running', 'passed', 'failed')", name: "scenario_runs_status_known"
  end
end
