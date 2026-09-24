module FakeStripe
  # How the fake provider decides whether a charge succeeds. It uses only what the charge
  # request carries (the card) and its own outbox (past charges), never the engine's data.
  module Charges
    class << self
      # nil when the charge succeeds, otherwise a Stripe-style failure code.
      def failure_code(payment_method, at:)
        return "no_payment_method" if payment_method.nil?
        # A real card stops working once its expiry month is over, whatever the token says.
        return "expired_card" if at > Time.utc(payment_method[:exp_year], payment_method[:exp_month]).end_of_month

        card = TestCards.fetch(payment_method[:token])
        case card.behavior
        when "succeeds" then nil
        when "succeeds_after_failures" then previous_failures(payment_method[:id]) < failures_before_success(card) ? "card_declined" : nil
        else card.behavior
        end
      end

      def attempts_for(invoice_id)
        charge_events.where("json_extract(payload, '$.data.object.invoice') = ?", invoice_id).count
      end

      private

      def previous_failures(payment_method_id)
        charge_events.where(event_type: "charge.failed")
          .where("json_extract(payload, '$.data.object.payment_method') = ?", payment_method_id).count
      end

      # pm_card_succeedsAfterFailures_2 → 2
      def failures_before_success(card)
        card.token[/_(\d+)\z/, 1].to_i
      end

      def charge_events
        MockedWebhookEvent.where(event_type: %w[charge.succeeded charge.failed])
      end
    end
  end
end
