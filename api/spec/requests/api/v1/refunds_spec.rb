require "rails_helper"

RSpec.describe "Refunds", type: :request do
  before { freeze_clock_at(Time.utc(2026, 10, 1)) }

  let!(:invoice) { subscribe(customer_with_card).invoices.sole }

  def json
    response.parsed_body
  end

  def refund(**body)
    post "/api/v1/invoices/#{invoice.id}/refunds", params: body, as: :json, headers: { "Idempotency-Key" => "refund-#{body.hash}" }
  end

  it "refunds part of the invoice and answers with the settled invoice" do
    refund(amount_cents: 1500, destination: "original_method", reason: "service_issue")

    expect(response).to have_http_status(:created)
    expect(json).to include("amount_refunded_cents" => 1500, "refundable_cents" => 3400)
    expect(json["refunds"].sole).to include("amount_cents" => 1500, "status" => "succeeded", "reason" => "service_issue")
  end

  it "refuses to refund more than is left" do
    refund(amount_cents: 4901)

    expect(response).to have_http_status(:unprocessable_content)
    expect(json["error"]).to include("code" => "refund_exceeds_refundable", "details" => include("refundable_cents" => 4900))
  end

  it "rejects a non-numeric amount" do
    refund(amount_cents: "12.50")

    expect(json.dig("error", "code")).to eq("invalid_amount")
  end

  it "shows refunds and the refundable amount on the invoice" do
    refund(amount_cents: 900, destination: "credit_balance")

    get "/api/v1/invoices/#{invoice.id}"

    expect(json).to include("refundable_cents" => 4000)
    expect(json["refunds"].sole).to include("destination" => "credit_balance", "status" => "succeeded")
  end
end
