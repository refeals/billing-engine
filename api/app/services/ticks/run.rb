module Ticks
  # Executes the daily steps for one simulated day. Later features append their step
  # classes to STEPS; the order is explicit because steps depend on each other (e.g.
  # renewals must run before dunning looks for failed invoices).
  class Run
    STEPS = [
      # Before trial conversion: a trial scheduled to cancel must end, not convert.
      Ticks::CancelAtPeriodEnd,
      Ticks::EndTrials,
      Ticks::ResumePaused,
      # Last: a subscription resumed today with an old period gets current dates.
      Ticks::RenewPeriods
    ].freeze

    # Each step responds to `.call(at:)` and returns a hash of counters for the tick report.
    def self.call(at:, steps: STEPS)
      steps.each_with_object(Hash.new(0)) do |step, report|
        step.call(at: at).each { |counter, value| report[counter] += value }
      end.to_h
    end
  end
end
