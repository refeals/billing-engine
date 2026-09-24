require "rails_helper"

RSpec.describe Webhooks::Ingest do
  let(:subscription) { create(:subscription) }

  before { freeze_clock_at(Time.utc(2026, 10, 5)) }

  describe "idempotency" do
    it "processes an event once, however many times it is delivered" do
      event = subscription_event(subscription)

      first = ingest(event)
      second = ingest(event)
      third = ingest(event)

      expect([ first, second, third ].map(&:status)).to eq(%i[processed duplicate duplicate])
      expect(WebhookEvent.count).to eq(1)
      expect(WebhookEvent.sole).to have_attributes(processing_status: "processed", duplicate_deliveries_count: 2, attempts: 1)
      expect(BillingEvent.of_type("provider.subscription_observed").count).to eq(1)
      expect(BillingEvent.of_type("webhook.duplicate_received").count).to eq(2)
    end

    # Two deliveries can both claim the row before either finishes; the lock + re-read in
    # ProcessEvent lets only one of them apply the event.
    it "applies the event once when two deliveries race past the claim" do
      ingest(stripe_event(type: "invoice.finalized", object: { id: "in_1" }, id: "evt_race"))
      row = WebhookEvent.sole
      row.update_columns(processing_status: "received", processed_at: nil)
      stale_copy = WebhookEvent.find(row.id)
      handler = class_double(Webhooks::Handlers::SubscriptionObserved, call: :processed)
      allow(Webhooks::Handlers::Registry).to receive(:for).and_return(handler)

      Webhooks::ProcessEvent.call(row)
      result = Webhooks::ProcessEvent.call(stale_copy)

      expect(result.status).to eq(:duplicate)
      expect(handler).to have_received(:call).once
    end
  end

  describe "failures" do
    let(:event) { subscription_event(subscription) }

    it "marks the event failed, keeps the error and lets the next delivery retry it" do
      allow(Webhooks::Handlers::SubscriptionObserved).to receive(:call).and_raise(RuntimeError, "database hiccup")

      result = ingest(event)

      expect(result.status).to eq(:failed)
      expect(WebhookEvent.sole).to have_attributes(processing_status: "failed", attempts: 1,
        last_error: "RuntimeError: database hiccup")
      expect(BillingEvent.of_type("webhook.failed").sole.webhook_event_id).to eq(WebhookEvent.sole.id)

      allow(Webhooks::Handlers::SubscriptionObserved).to receive(:call).and_call_original
      expect(ingest(event).status).to eq(:processed)
      expect(WebhookEvent.sole).to have_attributes(processing_status: "processed", attempts: 2, last_error: nil,
        duplicate_deliveries_count: 0)
    end

    it "rolls back everything the handler wrote before failing" do
      allow(Webhooks::Handlers::SubscriptionObserved).to receive(:call).and_wrap_original do |original, *args|
        original.call(*args)
        raise "failed after writing"
      end

      ingest(event)

      expect(BillingEvent.of_type("provider.subscription_observed")).to be_empty
      expect(subscription.reload.last_provider_event_at).to be_nil
    end

    it "fails an event about a subscription we don't know, so the provider retries it" do
      result = ingest(stripe_event(type: "customer.subscription.updated", object: { id: "sub_unknown", status: "active" }))

      expect(result.status).to eq(:failed)
      expect(WebhookEvent.sole.last_error).to include("Webhooks::UnknownObject")
    end
  end

  describe "ordering" do
    it "skips an event older than one already applied to the same subscription" do
      ingest(subscription_event(subscription, status: "past_due", created: Time.utc(2026, 10, 2)))
      result = ingest(subscription_event(subscription, status: "active", created: Time.utc(2026, 10, 1)))

      expect(result.status).to eq(:skipped_stale)
      expect(subscription.reload.last_provider_event_at).to eq(Time.utc(2026, 10, 2))
      expect(BillingEvent.of_type("provider.subscription_observed").count).to eq(1)
      expect(BillingEvent.of_type("webhook.skipped_stale").count).to eq(1)
    end

    it "still processes an older event about a different subscription" do
      other = create(:subscription)
      ingest(subscription_event(subscription, created: Time.utc(2026, 10, 2)))

      expect(ingest(subscription_event(other, created: Time.utc(2026, 10, 1))).status).to eq(:processed)
    end

    it "processes events with the same timestamp" do
      created = Time.utc(2026, 10, 2)
      ingest(subscription_event(subscription, created: created))

      expect(ingest(subscription_event(subscription, created: created)).status).to eq(:processed)
    end
  end

  describe "what a processed event leaves behind" do
    it "attributes the changes to the webhook and links them to the inbox row" do
      ingest(subscription_event(subscription, status: "past_due"))

      observed = BillingEvent.of_type("provider.subscription_observed").sole
      expect(observed).to have_attributes(actor_type: "webhook", webhook_event_id: WebhookEvent.sole.id,
        subscription_id: subscription.id)
      expect(observed.data["context"]).to include("provider_status" => "past_due", "engine_status" => "active",
        "matches" => false)
    end

    it "doesn't bump lock_version, so an operator's open screen stays valid" do
      expect { ingest(subscription_event(subscription)) }.not_to change { subscription.reload.lock_version }
    end

    it "stores the event with provider and simulated times" do
      ingest(subscription_event(subscription, id: "evt_1", created: Time.utc(2026, 10, 1, 12)))

      expect(WebhookEvent.sole).to have_attributes(provider_event_id: "evt_1", event_type: "customer.subscription.updated",
        provider_object_id: subscription.provider_subscription_id, provider_created_at: Time.utc(2026, 10, 1, 12),
        received_at: Time.utc(2026, 10, 5))
    end
  end

  it "acknowledges event types it has no handler for" do
    result = ingest(stripe_event(type: "invoice.finalized", object: { id: "in_1" }))

    expect(result.status).to eq(:ignored_unhandled)
    expect(WebhookEvent.sole.processing_status).to eq("ignored_unhandled")
  end

  describe "signature verification" do
    it "accepts unsigned events while the simulator is on" do
      expect(Webhooks::SignatureVerifier.current).to eq(Webhooks::NullSignatureVerifier)
    end

    it "fails closed when the simulator is off, since nothing verifies signatures yet" do
      allow(Rails.configuration.x).to receive(:simulator_enabled).and_return(false)

      expect { ingest(stripe_event(type: "invoice.finalized", object: { id: "in_1" })) }
        .to raise_error(Webhooks::InvalidSignature)
      expect(WebhookEvent.count).to eq(0)
    end
  end

  describe "malformed payloads" do
    it "rejects invalid JSON" do
      expect { described_class.call(raw_body: "{not json") }
        .to raise_error(Webhooks::InvalidPayload, /not valid JSON/)
    end

    it "rejects events without an id, type or object id" do
      expect { described_class.call(raw_body: { type: "invoice.paid", created: 1, data: { object: {} } }.to_json) }
        .to raise_error(Webhooks::InvalidPayload, /id, data.object.id/)
    end

    # A 500 here would make the provider resend the same broken body forever.
    it "rejects data or data.object that is not an object, instead of crashing" do
      [ "oops", { object: [ "a" ] }, { object: "in_1" } ].each do |data|
        body = { id: "evt_bad", type: "invoice.paid", created: 1, data: data }.to_json

        expect { described_class.call(raw_body: body) }.to raise_error(Webhooks::InvalidPayload, /data.object/)
      end
      expect(WebhookEvent.count).to eq(0)
    end

    it "rejects a non-numeric created timestamp" do
      event = stripe_event(type: "invoice.finalized", object: { id: "in_1" }).merge(created: "yesterday")

      expect { ingest(event) }.to raise_error(Webhooks::InvalidPayload, /Unix timestamp/)
      expect(WebhookEvent.count).to eq(0)
    end
  end
end
