module Webhooks
  module Handlers
    # Which handler processes which event type. Types without a handler are acknowledged as
    # `ignored_unhandled` (200), so the provider doesn't retry them forever.
    module Registry
      HANDLERS = {
        "customer.subscription.created" => SubscriptionObserved,
        "customer.subscription.updated" => SubscriptionObserved,
        "customer.subscription.deleted" => SubscriptionObserved,
        "charge.succeeded" => ChargeRecorded,
        "charge.failed" => ChargeRecorded,
        "invoice.paid" => InvoicePaid,
        "invoice.payment_failed" => InvoicePaymentFailed,
        "refund.updated" => RefundUpdated,
        "charge.refunded" => ChargeRefunded
      }.freeze

      def self.for(event_type)
        HANDLERS[event_type]
      end
    end
  end
end
