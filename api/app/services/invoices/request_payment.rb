module Invoices
  # Asks the provider to collect what an invoice still owes, with the customer's current
  # default card. The answer only comes back as webhooks (invoice.paid / payment_failed).
  class RequestPayment < ApplicationService
    def initialize(invoice)
      @invoice = invoice
    end

    def call
      subscription = @invoice.subscription
      card = @invoice.customer.default_payment_method

      PaymentGateway.current.pay_invoice(
        invoice: @invoice.provider_invoice_id,
        subscription: subscription.provider_subscription_id,
        customer: @invoice.customer.provider_customer_id,
        amount_cents: @invoice.amount_due_cents,
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
