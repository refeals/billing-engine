require "rails_helper"

RSpec.describe "Simulator clock", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:real_now) { Time.zone.parse("2026-10-01 12:00:00") }

  around { |example| travel_to(real_now) { example.run } }

  def json
    response.parsed_body
  end

  it "returns the current simulated time" do
    get "/api/v1/simulator/clock"

    expect(response).to have_http_status(:ok)
    expect(json).to eq("now" => "2026-10-01T12:00:00Z")
  end

  it "advances the clock and returns the tick report" do
    post "/api/v1/simulator/clock/advance", params: { days: 3 }, as: :json

    expect(response).to have_http_status(:ok)
    expect(json).to include("now" => "2026-10-04T12:00:00Z", "ticks_run" => 3)
    expect(json["tick_report"]).to include("subscriptions_canceled" => 0, "trials_converted" => 0, "periods_renewed" => 0)
  end

  it "rejects an invalid number of days with the standard error shape" do
    post "/api/v1/simulator/clock/advance", params: { days: 0 }, as: :json

    expect(response).to have_http_status(:unprocessable_content)
    expect(json["error"]).to include("code" => "invalid_days", "details" => include("min" => 1, "max" => 30))
  end

  it "requires the days parameter" do
    post "/api/v1/simulator/clock/advance", params: {}, as: :json

    expect(response).to have_http_status(:bad_request)
    expect(json.dig("error", "code")).to eq("bad_request")
  end

  it "resets the clock to real time" do
    post "/api/v1/simulator/clock/advance", params: { days: 5 }, as: :json
    post "/api/v1/simulator/clock/reset"

    expect(response).to have_http_status(:ok)
    expect(json).to eq("now" => "2026-10-01T12:00:00Z")
  end
end
