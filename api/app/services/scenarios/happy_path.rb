module Scenarios
  class HappyPath < Base
    scenario key: "happy_path", title: "Happy path",
      description: "A trial converts when the provider reports the first payment, then renews twice."

    def steps
      customer
      subscribe("starter")
      expect_that("the subscription starts in trial") { subscription.status == "trialing" }

      advance_to_period_end
      expect_that("the trial converted after invoice.paid") { subscription.status == "active" }
      expect_that("the first invoice is paid") { subscription.invoices.paid.count == 1 }

      2.times { advance_to_period_end }
      expect_that("two renewals were invoiced and paid") { subscription.invoices.paid.count == 3 }
      expect_that("it is still active") { subscription.status == "active" }
    end
  end
end
