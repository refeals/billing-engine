module Webhooks
  module Handlers
    # charge.succeeded / charge.failed: records the attempt. Whether the invoice is paid and
    # what happens to the subscription is decided by the invoice.* event that follows.
    class ChargeRecorded < Base
      def call
        invoice = find_invoice!(object["invoice"])
        PaymentAttemptRecorder.record!(
          invoice: invoice, charge_id: object["id"], status: object["status"], amount_cents: object["amount"],
          failure_code: object["failure_code"], payment_method_id: object["payment_method"], at: provider_created_at,
          metadata: object["metadata"]
        )
        :processed
      end
    end
  end
end
