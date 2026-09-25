require "rails_helper"

RSpec.describe "Reconciliation", type: :request do
  before { freeze_clock_at(Time.utc(2026, 10, 1)) }

  let!(:subscription) { subscribe(customer_with_card) }

  def json
    response.parsed_body
  end

  def disagree!
    FakeStripe::Gateway.emit_subscription_event(subscription.provider_subscription_id,
      snapshot: subscription.reload.provider_snapshot.merge(status: "past_due"))
  end

  it "runs, lists and shows runs" do
    disagree!

    post "/api/v1/reconciliation_runs", as: :json
    expect(response).to have_http_status(:created)
    expect(json).to include("triggered_by" => "admin", "subscriptions_checked" => 1, "discrepancies_opened" => 1)
    expect(json["discrepancies"].sole).to include("kind" => "status_mismatch", "internal_value" => "active", "expected_value" => "past_due",
      "available_resolutions" => %w[apply_expected resync_provider acknowledge])

    get "/api/v1/reconciliation_runs"
    expect(json["data"].first["discrepancies_found"]).to eq(1)
  end

  it "runs for one subscription" do
    post "/api/v1/reconciliation_runs", params: { subscription_id: subscription.id }, as: :json

    expect(json).to include("scope_subscription_id" => subscription.id, "discrepancies_found" => 0)
  end

  it "lists open discrepancies and resolves one" do
    disagree!
    post "/api/v1/reconciliation_runs", as: :json

    get "/api/v1/reconciliation_discrepancies", params: { status: "open", subscription_id: subscription.id }
    discrepancy = json["data"].sole

    post "/api/v1/reconciliation_discrepancies/#{discrepancy['id']}/resolve", params: { strategy: "resync_provider" }, as: :json
    expect(json).to include("status" => "resolved", "resolution" => "resync_provider", "available_resolutions" => [])

    get "/api/v1/subscriptions/#{subscription.id}"
    expect(json["open_discrepancies_count"]).to eq(0)
  end

  it "refuses an unavailable resolution" do
    disagree!
    post "/api/v1/reconciliation_runs", as: :json
    id = ReconciliationDiscrepancy.sole.id

    post "/api/v1/reconciliation_discrepancies/#{id}/resolve", params: { strategy: "redeliver" }, as: :json

    expect(response).to have_http_status(:unprocessable_content)
    expect(json.dig("error", "code")).to eq("resolution_not_available")
  end
end
