module Subscriptions
  # Shared by the operator's Resume and the tick that ends a timed pause.
  #
  # Pausing stops the billing clock. If the paid period is still running, it simply
  # continues. If it ended during the pause, a new period starts now and is billed now, so
  # the customer never pays for time spent paused and never gets a free stretch either.
  class Unpause < ApplicationService
    def initialize(subscription, reason:)
      @subscription = subscription
      @reason = reason
    end

    def call
      now = BillingClock.now
      period_over = @subscription.current_period_end <= now
      attributes = { paused_at: nil, resumes_at: nil }
      attributes.merge!(current_period_start: now, current_period_end: PlanPeriod.advance(now, @subscription.plan)) if period_over

      ActiveRecord::Base.transaction do
        Transition.call(@subscription, to: "active", reason: @reason, attributes: attributes)
        if period_over
          Invoices::Issue.call(subscription: @subscription, billing_reason: "subscription_cycle",
            period_start: @subscription.current_period_start, period_end: @subscription.current_period_end)
        end
        @subscription
      end
    end
  end
end
