module Scenarios
  class OutOfOrderEvents < Base
    scenario key: "out_of_order_events", title: "Out-of-order events",
      description: "A payment failure arrives a day after the payment that succeeded; the old event is skipped."

    def steps
      customer(card: "pm_card_chargeDeclined")
      drop_next("invoice.payment_failed")
      subscribe("studio")
      expect_that("the failure hasn't reached the engine yet") { subscription.status == "active" }

      advance_days(1)
      card("pm_card_visa")
      retry_payment
      expect_that("the retry paid the invoice") { subscription.invoices.sole.paid? }

      deliver_dropped("invoice.payment_failed")
      expect_that("the late failure was skipped as stale") { inbox_row("invoice.payment_failed").skipped_stale? }
      expect_that("it didn't undo the payment") { subscription.invoices.sole.paid? && subscription.status == "active" }
    end
  end
end
