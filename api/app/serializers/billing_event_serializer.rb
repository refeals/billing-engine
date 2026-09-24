class BillingEventSerializer
  def initialize(event)
    @event = event
  end

  def as_json(*)
    {
      id: @event.id,
      event_type: @event.event_type,
      actor_type: @event.actor_type,
      subject: @event.subject_type && { type: @event.subject_type, id: @event.subject_id },
      subscription_id: @event.subscription_id,
      customer_id: @event.customer_id,
      webhook_event_id: @event.webhook_event_id,
      data: @event.data,
      occurred_at: @event.occurred_at.iso8601,
      created_at: @event.created_at.iso8601
    }
  end
end
