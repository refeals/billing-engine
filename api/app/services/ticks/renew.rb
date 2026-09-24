module Ticks
  # Starts the next period of every active subscription whose period ended, and bills it.
  # past_due and paused subscriptions are not renewed: one waits for its unpaid invoice,
  # the other isn't billed while paused.
  class Renew
    def self.call(at:)
      due = Subscription.with_status("active").where(cancel_at_period_end: false).where(current_period_end: ..at)

      renewed = due.includes(:plan, :customer).find_each.count { |subscription| bill_next_period(subscription) }

      { renewal_invoices_issued: renewed }
    end

    def self.bill_next_period(subscription)
      # A change scheduled "at period end" takes effect now, so the new period is billed at
      # the new plan's price.
      scheduled = subscription.plan_changes.scheduled.to_a
      scheduled.each { |plan_change| PlanChanges::ApplyScheduled.call(plan_change) }
      subscription.reload if scheduled.any?

      period_start = subscription.current_period_end
      period_end = PlanPeriod.advance(period_start, subscription.plan)

      subscription.update!(current_period_start: period_start, current_period_end: period_end)
      Invoices::Issue.call(subscription: subscription, billing_reason: "subscription_cycle",
        period_start: period_start, period_end: period_end)
    end
  end
end
