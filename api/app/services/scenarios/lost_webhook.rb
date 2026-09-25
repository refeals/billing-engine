module Scenarios
  class LostWebhook < Base
    scenario key: "lost_webhook", title: "Lost webhook",
      description: "The provider's invoice.paid never arrives. Reconciliation flags it; resolve it on the Reconciliation screen."

    def steps
      customer
      drop_next("invoice.paid")
      subscribe("studio")
      expect_that("the engine still sees the invoice as open") { subscription.invoices.sole.open? }

      reconcile
      kinds = ReconciliationDiscrepancy.open.where(subscription_id: subscription.id).pluck(:kind)
      expect_that("reconciliation found the lost event") { kinds.include?("undelivered_event") }
      expect_that("and the invoice the provider considers paid") { kinds.include?("invoice_status_mismatch") }
    end
  end
end
