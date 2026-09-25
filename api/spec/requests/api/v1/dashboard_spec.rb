require "rails_helper"

RSpec.describe "Dashboard", type: :request do
  before { freeze_clock_at(Time.utc(2026, 10, 1, 9)) }

  it "returns the billing health summary" do
    create(:subscription, status: "active", plan: create(:plan, amount_cents: 2_900))

    get "/api/v1/dashboard/summary"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include(
      "simulated_now" => "2026-10-01T09:00:00Z",
      "mrr_cents" => 2_900,
      "paying_subscriptions" => 1,
      "open_discrepancies" => 0,
      "dunning" => { "open_cases" => 0, "amount_at_risk_cents" => 0, "by_step" => {} },
      "recent_events" => []
    )
    expect(response.parsed_body["subscriptions_by_status"]).to include("active" => 1, "canceled" => 0)
  end
end
