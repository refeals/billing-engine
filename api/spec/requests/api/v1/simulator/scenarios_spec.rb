require "rails_helper"

RSpec.describe "Scenario Lab", type: :request do
  before { freeze_clock_at(Time.utc(2026, 3, 16, 9)) }

  def json
    response.parsed_body
  end

  it "lists the scenarios" do
    get "/api/v1/simulator/scenarios"

    expect(json["data"].map { |scenario| scenario["key"] }).to include("happy_path", "lost_webhook", "partial_refund")
    expect(json["data"].first).to include("title", "description")
  end

  it "runs a scenario and returns its log, then lists it and its events" do
    post "/api/v1/simulator/scenarios/duplicate_webhook/run"

    expect(response).to have_http_status(:created)
    expect(json).to include("status" => "passed", "title" => "Duplicate webhook")
    expect(json["log"].map { |entry| entry["step"] }).to include("✓ the payment was recorded once")
    run_id = json["id"]

    get "/api/v1/simulator/scenarios/runs"
    expect(json["data"].first["id"]).to eq(run_id)

    get "/api/v1/simulator/events", params: { scenario_run_id: run_id }
    expect(json["data"].map { |event| event["event_type"] }).to include("invoice.paid", "charge.succeeded")
  end

  it "keeps listing runs of a scenario that no longer exists" do
    ScenarioRun.create!(scenario_key: "retired_story", status: "passed", started_at: BillingClock.now)

    get "/api/v1/simulator/scenarios/runs"

    expect(json["data"].first).to include("title" => "Retired story")
  end

  it "answers 404 for an unknown scenario" do
    post "/api/v1/simulator/scenarios/nope/run"
    expect(response).to have_http_status(:not_found)
  end

  it "refuses to reset without an explicit confirmation" do
    post "/api/v1/simulator/reset", as: :json

    expect(response).to have_http_status(:unprocessable_content)
    expect(json.dig("error", "code")).to eq("confirmation_required")
  end
end
