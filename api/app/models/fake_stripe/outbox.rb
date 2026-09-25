module FakeStripe
  # Everything the fake provider tells the engine goes through here: one row per event, in
  # emission order, delivered later by the Dispatcher. Like the real Stripe, the provider
  # never calls the engine directly.
  module Outbox
    API_VERSION = "2024-06-20"

    # `delivery: "drop"` records the event but never sends it (a lost webhook); `copies`
    # sends the same event several times (duplicate deliveries).
    def self.emit(type:, object:, subscription_id: nil, delivery: "deliver", copies: 1)
      delivery = "drop" if drop_requested?(type)
      event_id = ProviderIds.generate("evt")
      created_at = BillingClock.now

      event = MockedWebhookEvent.create!(
        event_id: event_id,
        event_type: type,
        api_version: API_VERSION,
        provider_object_id: object.fetch(:id),
        provider_subscription_id: subscription_id,
        provider_created_at: created_at,
        delivery_mode: delivery,
        delivery_status: delivery == "drop" ? "dropped" : "pending",
        copies: copies,
        scenario_run_id: Current.scenario_run&.id,
        payload: {
          id: event_id, object: "event", type: type, api_version: API_VERSION,
          created: created_at.to_i, data: { object: object }
        }
      )
      Dispatcher.schedule_flush unless event.dropped?
      event
    end

    # A scenario can ask the provider to lose the next event of a type (one shot), to show
    # what a lost webhook does to the engine.
    def self.drop_requested?(type)
      types = Current.drop_event_types
      return false unless types&.include?(type)

      Current.drop_event_types = types - [ type ]
      true
    end
    private_class_method :drop_requested?
  end
end
