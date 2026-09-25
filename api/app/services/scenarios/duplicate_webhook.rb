module Scenarios
  class DuplicateWebhook < Base
    scenario key: "duplicate_webhook", title: "Duplicate webhook",
      description: "The provider delivers the same invoice.paid three times; the engine applies it once."

    def steps
      customer
      subscribe("studio")
      redeliver("invoice.paid", times: 2)

      row = inbox_row("invoice.paid")
      expect_that("the inbox has one row for the event, with two duplicate deliveries") { row.duplicate_deliveries_count == 2 }
      expect_that("the payment was recorded once") { subscription.invoices.sole.payment_attempts.count == 1 }
      expect_that("the invoice is paid once") { subscription.invoices.sole.amount_paid_cents == @plans.fetch("studio").amount_cents }
    end
  end
end
