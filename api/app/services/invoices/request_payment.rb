module Invoices
  # Asks the provider to collect what an invoice still owes, with the customer's current
  # default card. The answer only comes back as webhooks (invoice.paid / payment_failed).
  class RequestPayment < ApplicationService
    # `metadata` travels with the charge and comes back on its events (like Stripe's
    # metadata), so the attempt can be linked to the dunning step that asked for it.
    def initialize(invoice, metadata: {})
      @invoice = invoice
      @metadata = metadata
    end

    # Only open invoices are collected. A paid one must never be charged again, and an
    # uncollectible one was given up on; every caller relies on this guard, not on its own.
    def call
      return nil unless @invoice.reload.open?

      subscription = @invoice.subscription
      card = @invoice.customer.default_payment_method

      PaymentGateway.current.pay_invoice(
        invoice: @invoice.provider_invoice_id,
        subscription: subscription.provider_subscription_id,
        customer: @invoice.customer.provider_customer_id,
        amount_cents: @invoice.amount_due_cents,
        metadata: @metadata,
        # The test token travels with the request, as card details would: the provider
        # decides the outcome from it without reading our tables.
        payment_method: card && {
          id: card.provider_payment_method_id, token: card.test_card_token,
          exp_month: card.exp_month, exp_year: card.exp_year
        }
      )
    end
  end
end
