class WebhookEventSerializer
  def initialize(webhook_event, detail: false)
    @webhook_event = webhook_event
    @detail = detail
  end

  def as_json(*)
    event = @webhook_event
    summary = {
      id: event.id,
      provider_event_id: event.provider_event_id,
      event_type: event.event_type,
      provider_object_id: event.provider_object_id,
      processing_status: event.processing_status,
      provider_created_at: event.provider_created_at.iso8601,
      received_at: event.received_at.iso8601,
      processed_at: event.processed_at&.iso8601,
      attempts: event.attempts,
      last_error: event.last_error,
      duplicate_deliveries_count: event.duplicate_deliveries_count,
      reprocessable: event.reprocessable?
    }
    return summary unless @detail

    summary.merge(
      payload: event.payload,
      billing_events: event.billing_events.map { |billing_event| BillingEventSerializer.new(billing_event).as_json }
    )
  end
end
