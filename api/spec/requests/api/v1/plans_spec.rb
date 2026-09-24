require "rails_helper"

RSpec.describe "Plans", type: :request do
  def json
    response.parsed_body
  end

  it "creates a plan and audits it" do
    post "/api/v1/plans", params: { code: "studio_pro", name: "Studio Pro", amount_cents: 9900, interval: "month", trial_days: 7 }, as: :json

    expect(response).to have_http_status(:created)
    expect(json).to include("code" => "studio_pro", "amount_cents" => 9900, "currency" => "USD", "active" => true)
    expect(BillingEvent.of_type("plan.created").sole.actor_type).to eq("admin")
  end

  it "returns field errors for an invalid plan" do
    post "/api/v1/plans", params: { code: "Bad Code", name: "", amount_cents: 0, interval: "week" }, as: :json

    expect(response).to have_http_status(:unprocessable_content)
    expect(json.dig("error", "details").keys).to contain_exactly("code", "name", "amount_cents", "interval")
  end

  it "ignores an attempt to set the currency" do
    post "/api/v1/plans", params: { code: "basic", name: "Basic", amount_cents: 1900, interval: "month", currency: "BRL" }, as: :json

    expect(json["currency"]).to eq("USD")
  end

  it "lists active plans by default and archived ones on request" do
    active = create(:plan, amount_cents: 1900)
    archived = create(:plan, archived_at: Time.utc(2026, 9, 1))

    get "/api/v1/plans"
    expect(json["data"].map { |plan| plan["id"] }).to eq([ active.id ])

    get "/api/v1/plans", params: { include_archived: true }
    expect(json["data"].map { |plan| plan["id"] }).to contain_exactly(active.id, archived.id)
  end

  it "archives a plan" do
    plan = create(:plan)

    post "/api/v1/plans/#{plan.id}/archive"

    expect(response).to have_http_status(:ok)
    expect(json["active"]).to be(false)
  end

  it "returns 404 for an unknown plan" do
    get "/api/v1/plans/0"
    expect(response).to have_http_status(:not_found)
  end
end
