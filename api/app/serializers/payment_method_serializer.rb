class PaymentMethodSerializer
  # `at` is passed in so a list reads the simulated clock once, not once per card.
  def initialize(payment_method, at: BillingClock.now)
    @payment_method = payment_method
    @at = at
  end

  def as_json(*)
    {
      id: @payment_method.id,
      provider_payment_method_id: @payment_method.provider_payment_method_id,
      test_card_token: @payment_method.test_card_token,
      brand: @payment_method.brand,
      last4: @payment_method.last4,
      exp_month: @payment_method.exp_month,
      exp_year: @payment_method.exp_year,
      is_default: @payment_method.is_default,
      expired: @payment_method.expired?(at: @at),
      behavior: @payment_method.behavior
    }
  end
end
