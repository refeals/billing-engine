module Ticks
  # PROVISIONAL until plan 07: converts a finished trial to active without charging. Plan 07
  # replaces this with an invoice, and the conversion then waits for the payment webhook.
  class EndTrials
    def self.call(at:)
      due = Subscription.with_status("trialing").where(cancel_at_period_end: false).where(trial_ends_at: ..at)

      converted = due.includes(:plan).find_each.count do |subscription|
        period_start = subscription.trial_ends_at
        Subscriptions::Transition.call(subscription, to: "active", reason: "trial_converted",
          attributes: { current_period_start: period_start, current_period_end: PlanPeriod.advance(period_start, subscription.plan) })
      end

      { trials_converted: converted }
    end
  end
end
