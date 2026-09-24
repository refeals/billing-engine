module FakeStripe
  # The fake provider's API, as the engine sees it through PaymentGateway. It only receives
  # plain values and only writes to its own outbox: it never reads the engine's tables, so
  # its event history is an independent record of what "the provider" believes.
  module Gateway
    class << self
      def create_customer(name:, email:)
        id = ProviderIds.generate("cus")
        Outbox.emit(type: "customer.created", object: { id: id, object: "customer", name: name, email: email })
        id
      end

      def attach_payment_method(customer:, token:, exp_month:, exp_year:)
        card = TestCards.fetch(token)
        id = ProviderIds.generate("pm")
        Outbox.emit(type: "payment_method.attached", object: {
          id: id, object: "payment_method", customer: customer,
          card: { brand: card.brand, last4: card.last4, exp_month: exp_month, exp_year: exp_year }
        })
        { id: id, brand: card.brand, last4: card.last4 }
      end

      def create_subscription(snapshot:)
        id = ProviderIds.generate("sub")
        Outbox.emit(type: "customer.subscription.created", object: subscription_object(id, snapshot), subscription_id: id)
        id
      end

      def update_subscription(id, snapshot:)
        emit_subscription_event(id, snapshot: snapshot)
        nil
      end

      # Also used by the simulator to make the provider report something (possibly
      # disagreeing with the engine, or never delivered).
      def emit_subscription_event(id, snapshot:, type: nil, delivery: "deliver", copies: 1)
        type ||= snapshot[:status] == "canceled" ? "customer.subscription.deleted" : "customer.subscription.updated"
        Outbox.emit(type: type, object: subscription_object(id, snapshot), subscription_id: id,
          delivery: delivery, copies: copies)
      end

      private

      # Stripe represents times as Unix timestamps.
      def subscription_object(id, snapshot)
        {
          id: id,
          object: "subscription",
          customer: snapshot[:customer],
          status: snapshot[:status],
          plan: { id: snapshot[:plan] },
          current_period_start: snapshot[:current_period_start]&.to_i,
          current_period_end: snapshot[:current_period_end]&.to_i,
          trial_end: snapshot[:trial_end]&.to_i,
          cancel_at_period_end: snapshot[:cancel_at_period_end],
          canceled_at: snapshot[:canceled_at]&.to_i
        }
      end
    end
  end
end
