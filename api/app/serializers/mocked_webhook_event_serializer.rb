class MockedWebhookEventSerializer
  # `inbox_ids` maps provider event ids to inbox rows, looked up once per page.
  def initialize(event, inbox_ids: {})
    @event = event
    @inbox_ids = inbox_ids
  end

  def self.inbox_ids_for(events)
    WebhookEvent.where(provider_event_id: events.map(&:event_id)).pluck(:provider_event_id, :id).to_h
  end

  def as_json(*)
    event = @event
    {
      id: event.id,
      event_id: event.event_id,
      event_type: event.event_type,
      provider_object_id: event.provider_object_id,
      provider_subscription_id: event.provider_subscription_id,
      provider_created_at: event.provider_created_at.iso8601,
      delivery_mode: event.delivery_mode,
      copies: event.copies,
      delivery_status: event.delivery_status,
      delivery_count: event.delivery_count,
      delivery_attempts: event.delivery_attempts,
      last_delivery_result: event.last_delivery_result,
      last_delivered_at: event.last_delivered_at&.iso8601,
      webhook_event_id: @inbox_ids[event.event_id],
      payload: event.payload
    }
  end
end
