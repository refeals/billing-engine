require "rails_helper"

RSpec.describe "Customers", type: :request do
  def json
    response.parsed_body
  end

  before { freeze_clock_at(Time.utc(2026, 10, 15)) }

  it "creates a customer with a provider id" do
    post "/api/v1/customers", params: { name: "Studio Flow", email: "Owner@StudioFlow.test" }, as: :json

    expect(response).to have_http_status(:created)
    expect(json).to include("name" => "Studio Flow", "email" => "owner@studioflow.test", "credit_balance_cents" => 0,
      "payment_methods" => [])
    expect(json["provider_customer_id"]).to start_with("cus_")
  end

  it "refuses a duplicate email whatever its case" do
    create(:customer, email: "owner@studioflow.test")

    post "/api/v1/customers", params: { name: "Other", email: "OWNER@studioflow.test" }, as: :json

    expect(response).to have_http_status(:unprocessable_content)
    expect(json.dig("error", "details", "email")).to include("has already been taken")
  end

  it "searches customers" do
    flow = create(:customer, name: "Studio Flow", email: "hello@flow.test")
    create(:customer, name: "Iron Gym", email: "hello@iron.test")

    get "/api/v1/customers", params: { q: "flow" }

    expect(json["data"].map { |customer| customer["id"] }).to eq([ flow.id ])
  end

  it "shows payment methods with their expiry evaluated at simulated time" do
    customer = create(:customer)
    create(:payment_method, customer: customer, exp_month: 9, exp_year: 2026, is_default: true)

    get "/api/v1/customers/#{customer.id}"

    expect(json["payment_methods"].sole).to include("last4" => "4242", "is_default" => true, "expired" => true,
      "behavior" => "succeeds")
  end

  describe "payment methods" do
    let(:customer) { create(:customer) }

    it "attaches a test card" do
      post "/api/v1/customers/#{customer.id}/payment_methods",
        params: { test_card: "pm_card_chargeDeclined", exp_month: 12, exp_year: 2028 }, as: :json

      expect(response).to have_http_status(:created)
      expect(json).to include("brand" => "visa", "last4" => "0002", "behavior" => "card_declined", "is_default" => true)
    end

    it "refuses an expired card" do
      post "/api/v1/customers/#{customer.id}/payment_methods",
        params: { test_card: "pm_card_visa", exp_month: 1, exp_year: 2026 }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "code")).to eq("card_expired")
    end

    it "makes another card the default" do
      create(:payment_method, customer: customer, is_default: true)
      other = create(:payment_method, customer: customer)

      post "/api/v1/customers/#{customer.id}/payment_methods/#{other.id}/make_default"

      expect(response).to have_http_status(:ok)
      expect(customer.reload.default_payment_method).to eq(other)
    end

    it "does not reach another customer's card" do
      stranger_card = create(:payment_method)

      post "/api/v1/customers/#{customer.id}/payment_methods/#{stranger_card.id}/make_default"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "credit ledger" do
    let(:customer) { create(:customer) }

    it "applies manual adjustments in both directions" do
      post "/api/v1/customers/#{customer.id}/credit_ledger_entries", params: { amount_cents: 1000, note: "Goodwill" }, as: :json
      post "/api/v1/customers/#{customer.id}/credit_ledger_entries", params: { amount_cents: -250, note: "Correction" }, as: :json

      expect(response).to have_http_status(:created)
      expect(json).to include("amount_cents" => -250, "balance_after_cents" => 750, "reason" => "manual_adjustment")

      get "/api/v1/customers/#{customer.id}/credit_ledger_entries"
      expect(json["data"].map { |entry| entry["amount_cents"] }).to eq([ -250, 1000 ])
    end

    it "refuses to go below zero" do
      post "/api/v1/customers/#{customer.id}/credit_ledger_entries", params: { amount_cents: -1, note: "Oops" }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "code")).to eq("insufficient_credit")
    end

    it "refuses a zero or non-numeric amount" do
      [ 0, "abc", "1.5" ].each do |amount|
        post "/api/v1/customers/#{customer.id}/credit_ledger_entries", params: { amount_cents: amount, note: "x" }, as: :json
        expect(json.dig("error", "code")).to eq("invalid_amount")
      end
    end

    it "requires a note" do
      post "/api/v1/customers/#{customer.id}/credit_ledger_entries", params: { amount_cents: 100 }, as: :json

      expect(response).to have_http_status(:bad_request)
    end
  end

  it "lists the simulator's test cards" do
    get "/api/v1/simulator/test_cards"

    expect(json["data"].map { |card| card["token"] }).to include("pm_card_visa", "pm_card_chargeDeclinedExpiredCard")
  end
end
