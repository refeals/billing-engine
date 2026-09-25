module Webhooks
  module Handlers
    class InvoicePaymentFailed < Base
      def call
        invoice = find_invoice!(object["id"])
        return :skipped_stale if stale?(invoice)

        observe!(invoice)
        # A late failure report can't undo a payment that already went through.
        return :processed if invoice.paid?

        failure_code = object.dig("last_payment_error", "code")
        PaymentAttemptRecorder.record!(invoice: invoice, charge_id: object["charge"], status: "failed",
          amount_cents: object["amount_due"], failure_code: failure_code,
          payment_method_id: object["payment_method"], at: provider_created_at, metadata: object["metadata"])
        invoice.update!(attempt_count: object["attempt_count"].to_i)
        Audit.record(event_type: "invoice.payment_failed", subject: invoice,
          context: { failure_code: failure_code, attempt_count: invoice.attempt_count })

        subscription = invoice.subscription
        if %w[trialing active].include?(subscription.status)
          Subscriptions::Transition.call(subscription, to: "past_due", reason: "payment_failed",
            metadata: { invoice: invoice.number, failure_code: failure_code })
        end
        # Starts the dunning schedule, or continues the one already running for this invoice.
        Dunning::Open.call(invoice) if subscription.status == "past_due"
        :processed
      end
    end
  end
end
