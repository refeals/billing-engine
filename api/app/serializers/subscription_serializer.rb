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
      created_at: subscription.created_at.iso8601
    }
  end
end
