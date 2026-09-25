module Dunning
  # Starts the schedule for an unpaid invoice, or returns the case already running for it:
  # a second failure (the day-3 retry, a manual retry) continues the same case.
  class Open < ApplicationService
    def initialize(invoice)
      @invoice = invoice
    end

    def call
      existing = DunningCase.open.find_by(invoice_id: @invoice.id) ||
        DunningCase.open.find_by(subscription_id: @invoice.subscription_id)
      return existing if existing

      now = BillingClock.now
      dunning_case = DunningCase.create!(subscription: @invoice.subscription, invoice: @invoice, status: "open",
        started_at: now, next_step: Schedule.first, next_step_at: now)
      Audit.record(event_type: "dunning.opened", subject: dunning_case,
        context: { invoice: @invoice.number, amount_due_cents: @invoice.amount_due_cents })

      # Day 0 happens right away, in the same transaction as the failure that caused it.
      RunStep.call(dunning_case, Schedule.first, at: now, subscription: @invoice.subscription)
      dunning_case
    end
  end
end
