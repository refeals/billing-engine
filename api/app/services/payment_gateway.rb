# The engine's only door to the payment provider. Everything the engine asks the provider
# goes through `PaymentGateway.current`; replacing the fake with real Stripe means writing
# one module with these methods and returning it here.
#
#   create_customer(name:, email:)                               → "cus_…"
#   attach_payment_method(customer:, token:, exp_month:, exp_year:) → { id:, brand:, last4: }
#   create_subscription(snapshot:)                               → "sub_…"
#   update_subscription(id, snapshot:)                           → nil
#   create_invoice(snapshot:)                                    → "in_…"
#   pay_invoice(invoice:, subscription:, customer:, amount_cents:, payment_method:) → nil
#   refund(charge:, amount_cents:, reason:, payment_method:)     → "re_…"
#
# Return values are identifiers and card details only. Outcomes (a charge succeeded, a
# subscription changed at the provider) always come back later as webhooks, so the engine
# can't rely on a shortcut the real provider doesn't offer.
module PaymentGateway
  def self.current
    FakeStripe::Gateway
  end
end
