require "rails_helper"

RSpec.describe "Dunning cases", type: :request do
  before { freeze_clock_at(Time.utc(2026, 10, 1)) }

  let!(:subscription) { subscribe(customer_with_card("pm_card_chargeDeclined")).reload }

  def json
    response.parsed_body
  end

  it "lists open and closed cases" do
    get "/api/v1/dunning_cases", params: { status: "open" }
    expect(json["data"].sole).to include("status" => "open", "last_step" => "day_0_notice", "next_step" => "day_3_retry")
    expect(json["data"].sole["invoice"]).to include("total_cents" => 4900, "amount_due_cents" => 4900, "status" => "open")

    advance_days(14)

    get "/api/v1/dunning_cases", params: { status: "open" }
    expect(json["data"]).to be_empty
    get "/api/v1/dunning_cases", params: { status: "closed" }
    expect(json["data"].sole).to include("status" => "exhausted")
  end

  it "rejects an unknown status filter" do
    get "/api/v1/dunning_cases", params: { status: "maybe" }
    expect(json.dig("error", "code")).to eq("invalid_filter")
  end

  it "shows steps, notifications and linked attempts" do
    advance_days(3)

    get "/api/v1/dunning_cases/#{DunningCase.sole.id}"

    expect(json["steps"].map { |step| step["step"] }).to eq(%w[day_0_notice day_3_retry])
    expect(json["notifications"].map { |notification| notification["kind"] }).to eq(%w[payment_failed payment_retry])
    expect(json["payment_attempts"].last).to include("status" => "failed", "dunning_step_id" => DunningStep.last.id)
  end

  it "includes the open case on the subscription and the notifications on the customer" do
    get "/api/v1/subscriptions/#{subscription.id}"
    expect(json["open_dunning_case"]).to include("next_step" => "day_3_retry")

    get "/api/v1/customers/#{subscription.customer_id}/notifications"
    expect(json["data"].sole).to include("kind" => "payment_failed", "subject" => "Your payment didn't go through")
  end
end
