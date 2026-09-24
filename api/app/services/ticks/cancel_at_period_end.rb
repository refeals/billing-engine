module Ticks
  # Carries out cancellations the operator scheduled for the end of the period.
  class CancelAtPeriodEnd
    def self.call(at:)
      due = Subscription.live.where(cancel_at_period_end: true).where(current_period_end: ..at)

      canceled = due.find_each.count do |subscription|
        Subscriptions::Transition.call(subscription, to: "canceled", reason: "period_ended_after_cancel_request",
          attributes: { canceled_at: subscription.current_period_end, cancellation_reason: "period_ended_after_cancel_request",
                        cancel_at_period_end: false })
      end

      { subscriptions_canceled: canceled }
    end
  end
end
