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

      def create_invoice(snapshot:)
        id = ProviderIds.generate("in")
        Outbox.emit(type: "invoice.finalized", subscription_id: snapshot[:subscription], object: {
          id: id, object: "invoice", status: "open", customer: snapshot[:customer],
          subscription: snapshot[:subscription], number: snapshot[:number],
          total: snapshot[:total_cents], amount_due: snapshot[:amount_due_cents], currency: "usd"
        })
        id
      end

      # Tries to collect an invoice. Nothing is returned: like Stripe, the outcome is only
      # reported through events (charge.* then invoice.paid / invoice.payment_failed).
      def pay_invoice(invoice:, subscription:, customer:, amount_cents:, payment_method:)
        # Nothing to collect (e.g. fully covered by credit): paid without a charge.
        if amount_cents.zero?
          emit_invoice_event("invoice.paid", invoice, subscription, customer,
            status: "paid", amount_paid: 0, amount_due: 0, charge: nil, attempt_count: 0)
          return nil
        end

        failure = Charges.failure_code(payment_method, at: BillingClock.now)
        attempt_count = Charges.attempts_for(invoice) + 1
        charge_id = ProviderIds.generate("ch")

        Outbox.emit(type: failure ? "charge.failed" : "charge.succeeded", subscription_id: subscription, object: {
          id: charge_id, object: "charge", invoice: invoice, customer: customer,
          payment_method: payment_method&.fetch(:id), amount: amount_cents,
          status: failure ? "failed" : "succeeded", failure_code: failure
        })

        if failure
          emit_invoice_event("invoice.payment_failed", invoice, subscription, customer,
            status: "open", amount_paid: 0, amount_due: amount_cents, charge: charge_id,
            payment_method: payment_method&.fetch(:id), attempt_count: attempt_count,
            last_payment_error: { code: failure })
        else
          emit_invoice_event("invoice.paid", invoice, subscription, customer,
            status: "paid", amount_paid: amount_cents, amount_due: 0, charge: charge_id,
            payment_method: payment_method&.fetch(:id), attempt_count: attempt_count)
        end
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

      def emit_invoice_event(type, invoice, subscription, customer, **fields)
        Outbox.emit(type: type, subscription_id: subscription, object: {
          id: invoice, object: "invoice", subscription: subscription, customer: customer, currency: "usd", **fields
        })
      end

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
