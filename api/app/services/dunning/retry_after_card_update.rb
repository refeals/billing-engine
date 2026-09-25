module Dunning
  # A customer who fixes their card shouldn't wait for day 3: the unpaid invoice is retried
  # right away. The attempt is linked to the case but isn't a schedule step, so if it fails
  # the schedule simply continues.
  class RetryAfterCardUpdate < ApplicationService
    def initialize(customer)
      @customer = customer
    end

    def call
      DunningCase.open.joins(:subscription).where(subscriptions: { customer_id: @customer.id }).find_each do |dunning_case|
        next unless dunning_case.invoice.open_for_payment?

        Audit.record(event_type: "dunning.retry_after_card_update", subject: dunning_case,
          context: { invoice: dunning_case.invoice.number })
        Invoices::RequestPayment.call(dunning_case.invoice, metadata: { dunning_case_id: dunning_case.id })
      end
    end
  end
end
