module Dunning
  # A subscription canceled for any other reason (the operator, a scheduled cancellation)
  # stops its dunning. The invoice stays open: it is still owed.
  class CloseForCancellation < ApplicationService
    def initialize(subscription)
      @subscription = subscription
    end

    def call
      DunningCase.open.where(subscription_id: @subscription.id).find_each do |dunning_case|
        dunning_case.update!(status: "canceled", next_step: nil, next_step_at: nil, closed_at: BillingClock.now,
          closed_reason: "subscription_canceled")
        Audit.record(event_type: "dunning.closed", subject: dunning_case, context: { reason: "subscription_canceled" })
      end
    end
  end
end
