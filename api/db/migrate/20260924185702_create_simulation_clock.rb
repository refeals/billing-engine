class CreateSimulationClock < ActiveRecord::Migration[8.1]
  def change
    create_table :simulation_clock do |t|
      t.datetime :current_time, null: false
      t.datetime :updated_at, null: false
    end

    # There is exactly one clock for the whole system; the constraint makes a second
    # row impossible instead of merely unlikely.
    add_check_constraint :simulation_clock, "id = 1", name: "simulation_clock_single_row"
  end
end
