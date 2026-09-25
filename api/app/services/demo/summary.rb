module Demo
  # A compact picture of the data, used after seeding/resetting and by the seed specs.
  module Summary
    def self.call
      {
        simulated_now: BillingClock.now.iso8601,
        customers: Customer.count,
        subscriptions: Subscription.group(:status).count.sort.to_h,
        invoices: Invoice.group(:status).count.sort.to_h,
        open_dunning_cases: DunningCase.open.group(:last_step).count.sort.to_h,
        refunds: Refund.group(:destination).count.sort.to_h,
        customers_with_credit: Customer.where("credit_balance_cents > 0").count,
        open_discrepancies: ReconciliationDiscrepancy.open.count
      }
    end
  end
end
