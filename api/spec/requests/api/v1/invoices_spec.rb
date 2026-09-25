require "rails_helper"

RSpec.describe "Invoices", type: :request do
  before { freeze_clock_at(Time.utc(2026, 10, 1)) }

  def json
    response.parsed_body
  end

  it "lists invoices and filters them" do
    paid = subscribe(customer_with_card).invoices.sole
    open_invoice = subscribe(customer_with_card("pm_card_chargeDeclined")).invoices.sole

    get "/api/v1/invoices", params: { status: "open" }
    expect(json["data"].map { |row| row["id"] }).to eq([ open_invoice.id ])

    get "/api/v1/invoices", params: { subscription_id: paid.subscription_id }
    expect(json["data"].sole).to include("number" => paid.number, "status" => "paid", "payable" => false)
  end

  it "shows lines and payment attempts" do
    invoice = subscribe(customer_with_card).invoices.sole

    get "/api/v1/invoices/#{invoice.id}"

    expect(json["line_items"].sole).to include("kind" => "subscription", "amount_cents" => 4900)
    expect(json["payment_attempts"].sole).to include("status" => "succeeded", "card" => { "brand" => "visa", "last4" => "4242" })
  end

  it "retries an unpaid invoice with the current default card" do
    customer = customer_with_card("pm_card_chargeDeclined")
    invoice = subscribe(customer).invoices.sole
    # Swapped directly: through PaymentMethods::Attach the new card would trigger dunning's
    # immediate retry, and this spec is about the retry endpoint itself.
    customer.payment_methods.update_all(is_default: false)
    create(:payment_method, customer: customer, is_default: true)

    post "/api/v1/invoices/#{invoice.id}/retry_payment", headers: { "Idempotency-Key" => "retry-1" }

    expect(response).to have_http_status(:ok)
    expect(json).to include("status" => "paid", "attempt_count" => 2)
    expect(json["payment_attempts"].map { |attempt| attempt["status"] }).to eq(%w[failed succeeded])
    expect(BillingEvent.of_type("invoice.payment_retry_requested").sole.actor_type).to eq("admin")
  end

  it "refuses to retry an invoice with nothing to collect" do
    invoice = subscribe(customer_with_card).invoices.sole

    post "/api/v1/invoices/#{invoice.id}/retry_payment"

    expect(response).to have_http_status(:unprocessable_content)
    expect(json.dig("error", "code")).to eq("invoice_not_payable")
  end

  it "includes the default card on the subscription" do
    subscription = subscribe(customer_with_card)

    get "/api/v1/subscriptions/#{subscription.id}"

    expect(json["default_payment_method"]).to include("last4" => "4242", "expired" => false)
  end
end
