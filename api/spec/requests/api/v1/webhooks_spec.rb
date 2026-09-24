require "rails_helper"

RSpec.describe "Webhooks", type: :request do
  let(:subscription) { create(:subscription) }

  before { freeze_clock_at(Time.utc(2026, 10, 5)) }

  def json
    response.parsed_body
  end

  def deliver(event)
    post "/api/v1/webhooks/stripe", params: event.to_json, headers: { "Content-Type" => "application/json" }
  end

  describe "POST /webhooks/stripe" do
    it "answers 200 for the first delivery and for duplicates" do
      event = subscription_event(subscription)

      deliver(event)
      expect(response).to have_http_status(:ok)
      expect(json["status"]).to eq("processed")

      deliver(event)
      expect(response).to have_http_status(:ok)
      expect(json["status"]).to eq("duplicate")
    end

    it "answers 500 when the handler fails, so the provider retries" do
      allow(Webhooks::Handlers::SubscriptionObserved).to receive(:call).and_raise("boom")

      deliver(subscription_event(subscription))

      expect(response).to have_http_status(:internal_server_error)
      expect(json["status"]).to eq("failed")
    end

    it "answers 400 for a malformed payload" do
      post "/api/v1/webhooks/stripe", params: "{oops", headers: { "Content-Type" => "application/json" }

      expect(response).to have_http_status(:bad_request)
      expect(json.dig("error", "code")).to eq("invalid_payload")
    end

    it "answers 400, not 500, when data.object is not an object" do
      post "/api/v1/webhooks/stripe", params: { id: "evt_bad", type: "invoice.paid", created: 1, data: "oops" }.to_json,
        headers: { "Content-Type" => "application/json" }

      expect(response).to have_http_status(:bad_request)
      expect(json.dig("error", "code")).to eq("invalid_payload")
    end

    it "accepts the demo fixture used in the README" do
      deliver(JSON.parse(Rails.root.join("spec/fixtures/webhooks/invoice_paid.json").read))

      expect(json["status"]).to eq("ignored_unhandled")
    end
  end

  describe "inbox" do
    it "lists events newest first and filters by status" do
      deliver(subscription_event(subscription))
      deliver(stripe_event(type: "invoice.paid", object: { id: "in_1" }))

      get "/api/v1/webhook_events"
      expect(json["data"].map { |row| row["processing_status"] }).to eq(%w[ignored_unhandled processed])

      get "/api/v1/webhook_events", params: { status: "processed" }
      expect(json["data"].sole["event_type"]).to eq("customer.subscription.updated")
    end

    it "rejects an unknown status filter" do
      get "/api/v1/webhook_events", params: { status: "lost" }
      expect(json.dig("error", "code")).to eq("invalid_filter")
    end

    it "shows the payload and the billing events the webhook caused" do
      deliver(subscription_event(subscription))

      get "/api/v1/webhook_events/#{WebhookEvent.sole.id}"

      expect(json["payload"]["type"]).to eq("customer.subscription.updated")
      expect(json["billing_events"].map { |event| event["event_type"] }).to eq(%w[provider.subscription_observed])
    end

    it "reprocesses a failed event" do
      allow(Webhooks::Handlers::SubscriptionObserved).to receive(:call).and_raise("boom")
      deliver(subscription_event(subscription))
      allow(Webhooks::Handlers::SubscriptionObserved).to receive(:call).and_call_original

      post "/api/v1/webhook_events/#{WebhookEvent.sole.id}/reprocess"

      expect(response).to have_http_status(:ok)
      expect(json["status"]).to eq("processed")
      expect(BillingEvent.of_type("webhook.reprocess_requested").sole.actor_type).to eq("admin")
    end

    it "refuses to reprocess an event that is already done" do
      deliver(subscription_event(subscription))

      post "/api/v1/webhook_events/#{WebhookEvent.sole.id}/reprocess"

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "code")).to eq("already_processed")
      expect(BillingEvent.of_type("provider.subscription_observed").count).to eq(1)
    end
  end
end
