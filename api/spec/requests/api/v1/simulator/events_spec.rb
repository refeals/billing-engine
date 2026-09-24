require "rails_helper"

RSpec.describe "Simulator events", type: :request do
  let(:subscription) { create(:subscription) }

  before { freeze_clock_at(Time.utc(2026, 10, 5)) }

  def json
    response.parsed_body
  end

  def emit(**body)
    post "/api/v1/simulator/events", params: { subscription_id: subscription.id, type: "customer.subscription.updated", **body },
      as: :json
  end

  it "makes the provider report a subscription, delivered to the inbox right away" do
    emit

    expect(response).to have_http_status(:created)
    expect(json).to include("event_type" => "customer.subscription.updated", "delivery_status" => "delivered",
      "delivery_count" => 1, "last_delivery_result" => "processed")
    expect(json["webhook_event_id"]).to eq(WebhookEvent.sole.id)
  end

  it "lets the provider disagree with the engine" do
    emit(status: "past_due")

    observed = BillingEvent.of_type("provider.subscription_observed").sole
    expect(observed.data["context"]).to include("provider_status" => "past_due", "engine_status" => "active", "matches" => false)
  end

  it "sends copies as duplicates" do
    emit(copies: 3)

    expect(json["delivery_count"]).to eq(3)
    expect(WebhookEvent.sole.duplicate_deliveries_count).to eq(2)
  end

  it "drops an event, then delivers it on request" do
    emit(delivery: "drop")
    expect(json).to include("delivery_status" => "dropped", "webhook_event_id" => nil)

    post "/api/v1/simulator/events/#{json['id']}/deliver"

    expect(json).to include("delivery_status" => "delivered", "delivery_count" => 1)
    expect(WebhookEvent.count).to eq(1)
  end

  it "redelivers a delivered event as a duplicate" do
    emit
    post "/api/v1/simulator/events/#{json['id']}/deliver"

    expect(json["delivery_count"]).to eq(2)
    expect(WebhookEvent.sole.duplicate_deliveries_count).to eq(1)
  end

  it "validates the request" do
    emit(type: "invoice.paid")
    expect(json.dig("error", "code")).to eq("invalid_event")

    emit(copies: 9)
    expect(json.dig("error", "details")).to eq("copies" => 9)

    emit(status: "zombie")
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "lists the outbox newest first and filters by delivery status" do
    emit
    emit(delivery: "drop")

    get "/api/v1/simulator/events"
    expect(json["data"].map { |event| event["delivery_status"] }).to eq(%w[dropped delivered])

    get "/api/v1/simulator/events", params: { delivery_status: "dropped" }
    expect(json["data"].size).to eq(1)
  end
end
