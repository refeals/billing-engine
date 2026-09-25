module Dunning
  # The unpaid invoice got paid: the case ends, remaining steps never run, access returns.
  class Recover < ApplicationService
    def initialize(dunning_case, subscription:)
      @dunning_case = dunning_case
      @subscription = subscription
    end

    def call
      now = BillingClock.now
      @dunning_case.update!(status: "recovered", next_step: nil, next_step_at: nil, closed_at: now,
        closed_reason: "payment_received")

      if @subscription.access_suspended_at
        @subscription.update!(access_suspended_at: nil)
        Audit.record(event_type: "subscription.access_restored", subject: @subscription,
          before: { access_suspended: true }, after: { access_suspended: false })
      end

      Audit.record(event_type: "dunning.recovered", subject: @dunning_case,
        context: { invoice: @dunning_case.invoice.number, last_step: @dunning_case.last_step })
      Notify.call(@dunning_case, "payment_recovered")
      @dunning_case
    end
  end
end
