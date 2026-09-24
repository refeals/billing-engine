module Webhooks
  module Handlers
    # The only place an invoice becomes paid: the engine never assumes a charge worked.
    class InvoicePaid < Base
      def call
        invoice = find_invoice!(object["id"])
        return :skipped_stale if stale?(invoice)

        observe!(invoice)
        PaymentAttemptRecorder.record!(invoice: invoice, charge_id: object["charge"], status: "succeeded",
          amount_cents: object["amount_paid"], payment_method_id: object["payment_method"], at: provider_created_at)
        return :processed if invoice.paid?

        before = invoice.slice(:status, :amount_paid_cents, :amount_due_cents)
        invoice.update!(status: "paid", amount_paid_cents: object["amount_paid"], amount_due_cents: 0,
          paid_at: provider_created_at, attempt_count: object["attempt_count"].to_i)
        Audit.record(event_type: "invoice.paid", subject: invoice, before: before,
          after: invoice.slice(:status, :amount_paid_cents, :amount_due_cents))

        activate(invoice.subscription)
        :processed
      end

      private

      # A paid invoice is what turns a trial into a paying subscription, or brings a
      # past_due one back.
      def activate(subscription)
        reason = { "trialing" => "trial_converted", "past_due" => "payment_recovered" }[subscription.status]
        Subscriptions::Transition.call(subscription, to: "active", reason: reason) if reason
      end
    end
  end
end
