require "rails_helper"

RSpec.describe "Billing events", type: :request do
  let(:day) { Time.zone.parse("2026-10-01 12:00:00") }

  def json
    response.parsed_body
  end

  def ids
    json["data"].map { |event| event["id"] }
  end

  it "lists events newest first with the list envelope" do
    older = create(:billing_event, occurred_at: day)
    newer = create(:billing_event, occurred_at: day + 1.day, event_type: "clock.reset")

    get "/api/v1/billing_events"

    expect(response).to have_http_status(:ok)
    expect(ids).to eq([ newer.id, older.id ])
    expect(json["meta"]).to eq(
      "page" => 1, "per_page" => 50, "total_count" => 2, "total_pages" => 1,
      "event_types" => [ "clock.day_advanced", "clock.reset" ]
    )
  end

  it "serializes every field" do
    clock = SimulationClock.create!(id: 1, current_time: day)
    event = create(:billing_event, subject: clock, subscription_id: 4, customer_id: 2, data: { "after" => { "now" => "x" } })

    get "/api/v1/billing_events"

    expect(json["data"].sole).to eq(
      "id" => event.id,
      "event_type" => "clock.day_advanced",
      "actor_type" => "admin",
      "subject" => { "type" => "SimulationClock", "id" => 1 },
      "subscription_id" => 4,
      "customer_id" => 2,
      "webhook_event_id" => nil,
      "data" => { "after" => { "now" => "x" } },
      "occurred_at" => "2026-10-01T12:00:00Z",
      "created_at" => event.created_at.iso8601
    )
  end

  describe "filters" do
    let!(:for_subscription) { create(:billing_event, subscription_id: 1, customer_id: 9, occurred_at: day) }
    let!(:for_customer) { create(:billing_event, customer_id: 2, event_type: "clock.reset", occurred_at: day + 2.days) }
    let!(:by_system) { create(:billing_event, actor_type: "system_job", occurred_at: day + 4.days) }

    it "filters by subscription" do
      get "/api/v1/billing_events", params: { subscription_id: 1 }
      expect(ids).to eq([ for_subscription.id ])
    end

    it "filters by customer" do
      get "/api/v1/billing_events", params: { customer_id: 2 }
      expect(ids).to eq([ for_customer.id ])
    end

    it "filters by event type" do
      get "/api/v1/billing_events", params: { event_type: "clock.reset" }
      expect(ids).to eq([ for_customer.id ])
    end

    it "filters by actor" do
      get "/api/v1/billing_events", params: { actor_type: "system_job" }
      expect(ids).to eq([ by_system.id ])
    end

    it "filters by an inclusive date range" do
      get "/api/v1/billing_events", params: { from: "2026-10-01", to: "2026-10-03" }
      expect(ids).to eq([ for_customer.id, for_subscription.id ])
    end

    it "keeps the full list of event types for the filter dropdown" do
      get "/api/v1/billing_events", params: { event_type: "clock.reset" }
      expect(json.dig("meta", "event_types")).to eq([ "clock.day_advanced", "clock.reset" ])
    end

    it "rejects an unknown actor" do
      get "/api/v1/billing_events", params: { actor_type: "intern" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to include("code" => "invalid_filter", "details" => { "actor_type" => "intern" })
    end

    it "rejects a date sent as an array" do
      get "/api/v1/billing_events?from[]=2026-10-01"

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "code")).to eq("invalid_filter")
    end

    it "rejects a malformed date" do
      get "/api/v1/billing_events", params: { from: "01/10/2026" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "code")).to eq("invalid_filter")
    end
  end

  describe "pagination" do
    before do
      rows = Array.new(51) { |index| { event_type: "clock.day_advanced", actor_type: "admin", data: {}, occurred_at: day + index.minutes, created_at: day } }
      BillingEvent.insert_all!(rows)
    end

    it "returns 50 per page and reports the totals" do
      get "/api/v1/billing_events"

      expect(json["data"].size).to eq(50)
      expect(json["meta"]).to include("total_count" => 51, "total_pages" => 2)
    end

    it "returns the remainder on the next page" do
      get "/api/v1/billing_events", params: { page: 2 }

      expect(json["data"].size).to eq(1)
      expect(json.dig("data", 0, "occurred_at")).to eq(day.iso8601)
    end

    it "treats an invalid page as the first" do
      get "/api/v1/billing_events", params: { page: "-3" }

      expect(json.dig("meta", "page")).to eq(1)
    end

    it "treats a page sent as an array as the first" do
      get "/api/v1/billing_events?page[]=2"

      expect(response).to have_http_status(:ok)
      expect(json.dig("meta", "page")).to eq(1)
    end
  end
end
