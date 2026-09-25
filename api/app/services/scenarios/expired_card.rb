module Scenarios
  class ExpiredCard < Base
    scenario key: "expired_card", title: "Card expires before renewal",
      description: "The card works today but expires at the end of the month; the renewal fails and dunning starts."

    def steps
      now = BillingClock.now
      customer(exp: [ now.month, now.year ])
      subscribe("studio")
      expect_that("the first payment went through") { subscription.invoices.sole.paid? }

      advance_to_period_end
      attempt = subscription.invoices.order(:id).last.payment_attempts.last
      expect_that("the renewal failed because the card expired") { attempt.failure_code == "expired_card" }
      expect_that("dunning started") { subscription.status == "past_due" && DunningCase.open.exists?(subscription_id: subscription.id) }
    end
  end
end
