module Subscriptions
  # Cancels now, or schedules the cancellation for the end of the current period (the
  # customer keeps what they already paid for).
  class Cancel < AdminAction
    def call
      options[:at_period_end] ? schedule : cancel_now
    end

    private

    def cancel_now
      with_guards("cancel_now") do
        Transition.call(subscription, to: "canceled", reason: "customer_requested",
          attributes: { canceled_at: now, cancellation_reason: "customer_requested", cancel_at_period_end: false })
      end
    end

    def schedule
      with_guards("cancel_at_period_end") do
        subscription.update!(cancel_at_period_end: true)
        Audit.record(event_type: "subscription.cancellation_scheduled", subject: subscription,
          before: { cancel_at_period_end: false }, after: { cancel_at_period_end: true },
          context: { cancels_at: subscription.current_period_end.iso8601 })
      end
    end
  end
end
