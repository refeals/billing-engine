require "rails_helper"

RSpec.describe FakeStripe::Dispatcher do
  let(:subscription) { create(:subscription) }
  let(:outbox) { FakeStripe::MockedWebhookEvent }

  before { freeze_clock_at(Time.utc(2026, 10, 5)) }

  def emit(**options)
    FakeStripe::Gateway.emit_subscription_event(subscription.provider_subscription_id,
      snapshot: subscription.provider_snapshot, **options)
  end

  it "delivers only after the transaction commits" do
    ActiveRecord::Base.transaction do
      emit
      expect(WebhookEvent.count).to eq(0)
    end

    expect(WebhookEvent.sole.processing_status).to eq("processed")
    expect(outbox.sole).to have_attributes(delivery_status: "delivered", delivery_count: 1, last_delivery_result: "processed")
  end

  it "never delivers an event whose transaction rolled back" do
    ActiveRecord::Base.transaction do
      emit
      raise ActiveRecord::Rollback
    end

    expect(outbox.count).to eq(0)
    expect(WebhookEvent.count).to eq(0)
  end

  it "delivers in emission order" do
    first = emit
    second = emit

    expect(WebhookEvent.order(:id).pluck(:provider_event_id)).to eq([ first.event_id, second.event_id ])
  end

  it "never delivers a dropped event, until someone redelivers it" do
    event = emit(delivery: "drop")

    expect(event.reload.delivery_status).to eq("dropped")
    expect(WebhookEvent.count).to eq(0)

    described_class.redeliver(event)
    expect(event.reload).to have_attributes(delivery_status: "delivered", delivery_count: 1)
    expect(WebhookEvent.sole.provider_event_id).to eq(event.event_id)
  end

  it "sends copies as duplicate deliveries of the same event" do
    event = emit(copies: 3)

    expect(event.reload.delivery_count).to eq(3)
    expect(WebhookEvent.sole).to have_attributes(processing_status: "processed", duplicate_deliveries_count: 2)
  end

  describe "when the inbox fails" do
    before { allow(Webhooks::Handlers::SubscriptionObserved).to receive(:call).and_raise("inbox down") }

    it "keeps the event pending and retries it on the next flush" do
      event = emit

      expect(event.reload).to have_attributes(delivery_status: "pending", delivery_attempts: 1, last_delivery_result: "failed")

      allow(Webhooks::Handlers::SubscriptionObserved).to receive(:call).and_call_original
      described_class.flush

      expect(event.reload).to have_attributes(delivery_status: "delivered", delivery_attempts: 2)
      expect(WebhookEvent.sole.processing_status).to eq("processed")
    end

    it "retries once per simulated day" do
      event = emit
      allow(Webhooks::Handlers::SubscriptionObserved).to receive(:call).and_call_original

      report = BillingClock.advance!(days: 1)[:tick_report]

      expect(report[:provider_deliveries_pending]).to eq(1)
      expect(event.reload.delivery_status).to eq("delivered")
    end

    it "puts a dropped event delivered by hand back in the retry queue when that delivery fails" do
      event = emit(delivery: "drop")

      described_class.redeliver(event)
      expect(event.reload).to have_attributes(delivery_status: "pending", last_delivery_result: "failed")

      allow(Webhooks::Handlers::SubscriptionObserved).to receive(:call).and_call_original
      described_class.flush
      expect(event.reload.delivery_status).to eq("delivered")
    end

    it "stops sending the remaining copies after a failed one" do
      event = emit(copies: 3)

      expect(event.reload.delivery_count).to eq(0)
      expect(WebhookEvent.sole.attempts).to eq(1)
    end
  end

  # Flushes run right after a caller's transaction committed; an error escaping here would
  # turn that caller's finished work into a 500.
  it "treats an unexpected inbox error as a failed delivery instead of raising" do
    allow(Webhooks::Ingest).to receive(:call).and_raise(ActiveRecord::StatementInvalid, "database is locked")

    event = nil
    expect { event = emit }.not_to raise_error
    expect(event.reload).to have_attributes(delivery_status: "pending", last_delivery_result: "failed")
  end

  it "also delivers events emitted while it is delivering" do
    allow(Webhooks::Handlers::SubscriptionObserved).to receive(:call).and_wrap_original do |original, event|
      FakeStripe::Outbox.emit(type: "invoice.created", object: { id: "in_1" }) if event.event_type == "customer.subscription.updated"
      original.call(event)
    end

    emit

    expect(outbox.pluck(:delivery_status)).to all(eq("delivered"))
    expect(WebhookEvent.pluck(:event_type)).to contain_exactly("customer.subscription.updated", "invoice.created")
  end
end
