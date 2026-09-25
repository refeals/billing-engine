module Scenarios
  class UpgradeMidCycle < Base
    scenario key: "upgrade_mid_cycle", title: "Upgrade mid-cycle",
      description: "Studio → Studio Pro on day 10: the unused part is credited, the rest of the period charged at once."

    def steps
      customer
      subscribe("studio")
      advance_days(10)
      quote = change_plan("studio_pro")

      invoice = subscription.invoices.where(billing_reason: "subscription_update").sole
      expect_that("a proration invoice was issued for exactly the previewed amount") { invoice.subtotal_cents == quote.net_cents }
      expect_that("it has a credit line and a charge line") { invoice.line_items.pluck(:kind) == %w[proration_credit proration_charge] }
      expect_that("it was paid") { invoice.paid? }
      expect_that("the billing anchor didn't move") { subscription.current_period_end == invoice.period_end }
    end
  end
end
