class CustomerSerializer
  def initialize(customer, detail: false)
    @customer = customer
    @detail = detail
  end

  def as_json(*)
    summary = {
      id: @customer.id,
      name: @customer.name,
      email: @customer.email,
      provider_customer_id: @customer.provider_customer_id,
      credit_balance_cents: @customer.credit_balance_cents,
      created_at: @customer.created_at.iso8601
    }
    return summary unless @detail

    now = BillingClock.now
    summary.merge(payment_methods: @customer.payment_methods.map { |card| PaymentMethodSerializer.new(card, at: now).as_json })
  end
end
