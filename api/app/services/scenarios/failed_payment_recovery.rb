module Scenarios
  class FailedPaymentRecovery < Base
    scenario key: "failed_payment_recovery", title: "Failed payment, recovered",
      description: "A renewal is declined; on day 4 of dunning the customer adds a working card, which is charged at once."

    def steps
      customer
      subscribe("studio")
      card("pm_card_chargeDeclined")
      advance_to_period_end
      expect_that("the renewal failed and the subscription is past_due") { subscription.status == "past_due" }
      expect_that("a dunning case opened") { DunningCase.open.exists?(subscription_id: subscription.id) }

      advance_days(4)
      expect_that("the day-3 retry ran and failed again") { DunningStep.joins(:dunning_case).exists?(step: "day_3_retry", dunning_cases: { subscription_id: subscription.id }) }

      card("pm_card_visa")
      expect_that("the new card was charged immediately and the subscription recovered") { subscription.status == "active" }
      expect_that("the dunning case is recovered") { DunningCase.where(subscription_id: subscription.id).last.recovered? }
      expect_that("no suspension or cancellation happened") { DunningStep.joins(:dunning_case).where(dunning_cases: { subscription_id: subscription.id }).count == 2 }
    end
  end
end
