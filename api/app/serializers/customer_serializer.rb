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
    summary.merge(
      payment_methods: @customer.payment_methods.map { |card| PaymentMethodSerializer.new(card, at: now).as_json },
      subscriptions: @customer.subscriptions.includes(:plan).map { |subscription| subscription_summary(subscription) }
    )
  end

  private

  def subscription_summary(subscription)
    {
      id: subscription.id,
      status: subscription.status,
      plan: subscription.plan.slice(:id, :name, :code),
      current_period_end: subscription.current_period_end.iso8601,
      cancel_at_period_end: subscription.cancel_at_period_end
    }
  end
end
