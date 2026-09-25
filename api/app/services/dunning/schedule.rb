module Dunning
  # What happens after a payment fails, in days since the failure. A constant on purpose:
  # the schedule is part of the product's promise to customers, changed by a code review,
  # not by a setting.
  module Schedule
    STEPS = {
      "day_0_notice" => 0,   # tell the customer the payment failed
      "day_3_retry" => 3,    # try the card again
      "day_7_suspend" => 7,  # suspend access (the subscription stays past_due)
      "day_14_cancel" => 14  # give up: cancel, invoice becomes uncollectible
    }.freeze

    OUTCOMES = {
      "day_0_notice" => "customer_notified",
      "day_3_retry" => "payment_retry_requested",
      "day_7_suspend" => "access_suspended",
      "day_14_cancel" => "subscription_canceled"
    }.freeze

    def self.first
      STEPS.keys.first
    end

    def self.after(step)
      STEPS.keys[STEPS.keys.index(step) + 1]
    end

    def self.due_at(dunning_case, step)
      dunning_case.started_at + STEPS.fetch(step).days
    end
  end
end
