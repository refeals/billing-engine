module Ticks
  # PROVISIONAL until plan 07: rolls the billing period of active subscriptions forward
  # without charging, so period dates stay truthful (a cancellation scheduled "at period
  # end" must happen at a future date, never at one that already passed). Plan 07 replaces
  # this with a renewal invoice.
  class RenewPeriods
    def self.call(at:)
      due = Subscription.with_status("active").where(cancel_at_period_end: false).where(current_period_end: ..at)

      renewed = due.includes(:plan).find_each.count do |subscription|
        before = subscription.slice(:current_period_start, :current_period_end).transform_values(&:iso8601)
        period_start = subscription.current_period_end
        period_end = PlanPeriod.advance(period_start, subscription.plan)
        # Catches up if several periods passed (e.g. after a long pause).
        period_start, period_end = period_end, PlanPeriod.advance(period_end, subscription.plan) while period_end <= at

        subscription.update!(current_period_start: period_start, current_period_end: period_end)
        Audit.record(event_type: "subscription.period_renewed", subject: subscription, before: before,
          after: subscription.slice(:current_period_start, :current_period_end).transform_values(&:iso8601))
      end

      { periods_renewed: renewed }
    end
  end
end
