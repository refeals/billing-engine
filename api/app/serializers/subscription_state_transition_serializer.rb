class SubscriptionStateTransitionSerializer
  def initialize(transition)
    @transition = transition
  end

  def as_json(*)
    @transition.slice(:id, :from_status, :to_status, :reason, :actor_type, :webhook_event_id, :billing_event_id, :metadata)
      .merge(occurred_at: @transition.occurred_at.iso8601)
  end
end
