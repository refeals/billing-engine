# The only source of "now" for the whole engine. Billing behavior spans weeks (trials,
# renewals, a 14-day dunning schedule), so the demo needs time it can fast-forward.
# Reading time anywhere else would make those flows impossible to reproduce.
module BillingClock
  MAX_ADVANCE_DAYS = 30

  class << self
    def now
      clock.current_time
    end

    # Runs one tick per simulated day so a step due on day 3 fires on day 3, even when
    # the operator jumps 7 days at once.
    def advance!(days:)
      days = parse_days(days)
      tick_report = Hash.new(0)

      days.times do
        ActiveRecord::Base.transaction do
          current = clock
          before = current.current_time
          current.update!(current_time: before + 1.day)
          Audit.record(event_type: "clock.day_advanced", subject: current, before: { now: before.iso8601 }, after: { now: current.current_time.iso8601 })

          # Whoever moved the clock, the work that falls due is done by the system.
          Current.set(actor: "system_job") do
            Ticks::Run.call(at: current.current_time).each { |counter, value| tick_report[counter] += value }
          end
        end
      end

      { now: now, ticks_run: days, tick_report: tick_report.to_h }
    end

    def reset!
      ActiveRecord::Base.transaction do
        current = clock
        before = current.current_time
        current.rewind_allowed = true
        current.update!(current_time: real_time)
        Audit.record(event_type: "clock.reset", subject: current, before: { now: before.iso8601 }, after: { now: current.current_time.iso8601 })
        current.current_time
      end
    end

    private

    # Two first reads can race to create the row. create_or_find_by! relies on the primary
    # key to pick a winner and returns the existing row to the loser instead of raising.
    def clock
      SimulationClock.find_by(id: 1) ||
        SimulationClock.create_or_find_by!(id: 1) { |created| created.current_time = real_time }
    end

    def real_time
      Time.current.change(usec: 0)
    end

    def parse_days(value)
      # Base 10 is explicit: Integer("010") would otherwise be read as octal (8 days).
      days = Integer(value.to_s, 10) if value.is_a?(Integer) || value.to_s.match?(/\A\d+\z/)
      return days if days&.between?(1, MAX_ADVANCE_DAYS)

      raise DomainError.new(
        "days must be a whole number between 1 and #{MAX_ADVANCE_DAYS}",
        code: "invalid_days",
        details: { min: 1, max: MAX_ADVANCE_DAYS, received: value }
      )
    end
  end
end
