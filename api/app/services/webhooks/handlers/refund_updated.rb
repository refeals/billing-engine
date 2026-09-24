module Webhooks
  module Handlers
    # Settles a card refund. Only the move out of `pending` touches amounts, so the same
    # event delivered twice (or a stale one) can never count a refund twice.
    class RefundUpdated < Base
      def call
        refund = Refund.find_by(provider_refund_id: object["id"]) || raise(UnknownObject, "No refund #{object['id']}")
        return :skipped_stale if stale?(refund)

        observe!(refund)
        return :processed unless refund.pending?

        object["status"] == "succeeded" ? succeed(refund) : fail(refund)
        :processed
      end

      private

      def succeed(refund)
        invoice = refund.invoice
        invoice.lock!
        refund.update!(status: "succeeded", completed_at: provider_created_at)
        invoice.update!(amount_refunded_cents: invoice.amount_refunded_cents + refund.amount_cents)
        Audit.record(event_type: "refund.succeeded", subject: refund,
          after: { status: "succeeded", invoice_amount_refunded_cents: invoice.amount_refunded_cents })
      end

      # A failed refund gives its amount back to what can still be refunded.
      def fail(refund)
        refund.update!(status: "failed", failure_reason: object["failure_reason"], completed_at: provider_created_at)
        Audit.record(event_type: "refund.failed", subject: refund,
          after: { status: "failed" }, context: { failure_reason: object["failure_reason"] })
      end
    end
  end
end
