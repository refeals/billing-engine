module Scenarios
  class DowngradeWithCredit < Base
    scenario key: "downgrade_with_credit", title: "Downgrade with credit",
      description: "Studio Pro → Studio on day 10: the unused difference becomes credit, spent by the next renewal."

    def steps
      customer
      subscribe("studio_pro")
      advance_days(10)
      quote = change_plan("studio")
      credit = quote.credit_to_balance_cents
      expect_that("the unused difference became credit") { @customer.reload.credit_balance_cents == credit }

      advance_to_period_end
      renewal = subscription.invoices.where(billing_reason: "subscription_cycle").last
      expect_that("the renewal spent the credit before charging the card") { renewal.credit_applied_cents == credit }
      expect_that("the balance is back to zero") { @customer.reload.credit_balance_cents.zero? }
    end
  end
end
