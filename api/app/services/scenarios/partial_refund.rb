module Scenarios
  class PartialRefund < Base
    scenario key: "partial_refund", title: "Partial refunds",
      description: "Two partial refunds (card and credit balance), then an over-refund that is refused."

    def steps
      customer
      subscribe("studio")
      refund(2_000, destination: "original_method")
      refund(1_500, destination: "credit_balance")

      invoice = subscription.invoices.sole
      expect_that("the card refund was settled by the provider") { invoice.refunds.to_original_method.sole.succeeded? }
      expect_that("the rest became credit") { @customer.reload.credit_balance_cents == 1_500 }
      expect_that("2,400 cents can still be refunded") { invoice.reload.refundable_cents == 2_400 }
      expect_refused("refunding 3,000 cents is refused", "refund_exceeds_refundable") do
        refund(3_000, destination: "original_method")
      end
    end
  end
end
