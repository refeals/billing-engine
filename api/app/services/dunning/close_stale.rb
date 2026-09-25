module Dunning
  # Closes a case whose subscription is no longer past_due although no payment closed it
  # (for example, an operator's reconciliation correction). Nothing is sent to the customer.
  class CloseStale < ApplicationService
    def initialize(dunning_case)
      @dunning_case = dunning_case
    end

    def call
      ActiveRecord::Base.transaction do
        @dunning_case.update!(status: "canceled", next_step: nil, next_step_at: nil, closed_at: BillingClock.now,
          closed_reason: "subscription_no_longer_past_due")
        Audit.record(event_type: "dunning.closed", subject: @dunning_case,
          context: { reason: "subscription_no_longer_past_due", subscription_status: @dunning_case.subscription.status })
      end
    end
  end
end
