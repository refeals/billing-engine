class SimulationClock < ApplicationRecord
  self.table_name = "simulation_clock"

  # Set only by BillingClock.reset!. Every other change must move time forward, because
  # later features order events, invoices and dunning steps by this clock.
  attribute :rewind_allowed, :boolean, default: false

  validates :current_time, presence: true
  validate :cannot_move_backwards, on: :update

  private

  def cannot_move_backwards
    return if rewind_allowed || current_time_was.nil? || current_time.nil?

    errors.add(:current_time, "cannot move backwards") if current_time < current_time_was
  end
end
