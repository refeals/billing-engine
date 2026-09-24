module Webhooks
  module Handlers
    # The provider's running total of what it refunded on a charge. Amounts are applied from
    # refund.updated (one event per refund); this one is only compared, so a disagreement
    # shows up in the audit log instead of being silently overwritten either way.
    class ChargeRefunded < Base
      def call
        attempt = PaymentAttempt.find_by(provider_charge_id: object["id"]) || raise(UnknownObject, "No charge #{object['id']}")
        engine_total = attempt.invoice.refunds.succeeded.to_original_method.sum(:amount_cents)

        Audit.record(event_type: "provider.charge_refunded", subject: attempt.invoice,
          context: { charge: object["id"], provider_amount_refunded_cents: object["amount_refunded"],
                     engine_amount_refunded_cents: engine_total, matches: object["amount_refunded"] == engine_total })
        :processed
      end
    end
  end
end
