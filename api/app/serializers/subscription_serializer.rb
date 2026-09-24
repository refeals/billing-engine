class SubscriptionSerializer
  def initialize(subscription)
    @subscription = subscription
  end

  def as_json(*)
    subscription = @subscription
    {
      id: subscription.id,
      provider_subscription_id: subscription.provider_subscription_id,
      status: subscription.status,
      customer: subscription.customer.slice(:id, :name, :email),
      plan: PlanSerializer.new(subscription.plan).as_json,
      current_period_start: subscription.current_period_start.iso8601,
      current_period_end: subscription.current_period_end.iso8601,
      trial_ends_at: subscription.trial_ends_at&.iso8601,
      cancel_at_period_end: subscription.cancel_at_period_end,
      canceled_at: subscription.canceled_at&.iso8601,
      cancellation_reason: subscription.cancellation_reason,
      paused_at: subscription.paused_at&.iso8601,
      resumes_at: subscription.resumes_at&.iso8601,
      access_suspended: subscription.access_suspended_at.present?,
      lock_version: subscription.lock_version,
      allowed_actions: subscription.allowed_actions,
      default_payment_method: default_payment_method,
      scheduled_plan_change: scheduled_plan_change,
      created_at: subscription.created_at.iso8601
    }
  end

  private

  def scheduled_plan_change
    change = @subscription.plan_changes.scheduled.first
    change && PlanChangeSerializer.new(change).as_json
  end

  def default_payment_method
    card = @subscription.customer.default_payment_method
    card && PaymentMethodSerializer.new(card).as_json.slice(:id, :brand, :last4, :exp_month, :exp_year, :expired, :behavior)
  end
end
