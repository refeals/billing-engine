module Ticks
  # A trial that ends is billed for its first paid period. The subscription stays trialing
  # until the provider reports the payment: invoice.paid turns it active, a failure makes it
  # past_due. The period moves on right away, like Stripe's, so the trial is never billed
  # twice.
  class EndTrials
    def self.call(at:)
      due = Subscription.with_status("trialing").where(cancel_at_period_end: false).where(current_period_end: ..at)

      invoiced = due.includes(:plan, :customer).find_each.count do |subscription|
        Ticks::Renew.bill_next_period(subscription)
      end

      { trial_invoices_issued: invoiced }
    end
  end
end
