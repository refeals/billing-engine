# Stripe-shaped event payloads for webhook specs.
module StripeEvents
  def stripe_event(type:, object:, id: "evt_#{SecureRandom.hex(8)}", created: Time.utc(2026, 10, 1, 12))
    {
      id: id,
      object: "event",
      type: type,
      api_version: "2024-06-20",
      created: created.to_i,
      data: { object: object }
    }
  end

  def subscription_event(subscription, type: "customer.subscription.updated", status: subscription.status, **options)
    stripe_event(type: type, object: { id: subscription.provider_subscription_id, object: "subscription", status: status },
      **options)
  end

  def ingest(event)
    Webhooks::Ingest.call(raw_body: event.to_json)
  end
end

RSpec.configure do |config|
  config.include StripeEvents
end
