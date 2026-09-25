module Scenarios
  class FullDunning < Base
    scenario key: "full_dunning", title: "Full dunning",
      description: "A renewal is declined and never paid: notice, retry on day 3, suspension on day 7, cancellation on day 14."

    def steps
      customer
      subscribe("studio")
      card("pm_card_chargeDeclined")
      advance_to_period_end
      expect_that("the renewal failed") { subscription.status == "past_due" }

      advance_days(7)
      expect_that("access is suspended on day 7") { subscription.access_suspended? }

      advance_days(7)
      dunning_case = DunningCase.where(subscription_id: subscription.id).last
      expect_that("the subscription is canceled on day 14") { subscription.status == "canceled" }
      expect_that("the case ran out") { dunning_case.exhausted? }
      expect_that("the unpaid invoice is uncollectible") { dunning_case.invoice.reload.uncollectible? }
      expect_that("the customer got four notices") { dunning_case.notifications.count == 4 }
    end
  end
end
