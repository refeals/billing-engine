class CreateDunningSteps < ActiveRecord::Migration[8.1]
  STEPS = %w[day_0_notice day_3_retry day_7_suspend day_14_cancel].freeze

  def change
    create_table :dunning_steps do |t|
      t.references :dunning_case, null: false, foreign_key: true, index: false
      t.string :step, null: false
      t.datetime :scheduled_at, null: false
      t.datetime :executed_at, null: false
      t.string :outcome, null: false
      t.datetime :created_at, null: false
    end

    # A step runs at most once per case: if the daily job runs twice, the second insert is
    # refused and the step does nothing.
    add_index :dunning_steps, [ :dunning_case_id, :step ], unique: true
    add_check_constraint :dunning_steps, "step IN (#{STEPS.map { |step| "'#{step}'" }.join(', ')})", name: "dunning_steps_step_known"

    create_append_only_triggers :dunning_steps
  end
end
