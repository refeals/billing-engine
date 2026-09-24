require "rails_helper"

RSpec.describe "Plan changes", type: :request do
  let(:start) { Time.utc(2026, 10, 1) }
  let(:basic) { create(:plan, name: "Basic", amount_cents: 4900, trial_days: 0) }
  let(:pro) { create(:plan, name: "Pro", amount_cents: 9900, trial_days: 0) }
  # The clock is set first: `let!` runs in definition order with `before` hooks.
  before { freeze_clock_at(start) }

  let!(:subscription) { Subscriptions::Create.call(customer: customer_with_card, plan: basic).reload }

  def json
    response.parsed_body
  end

  def preview(plan, strategy: nil)
    post "/api/v1/subscriptions/#{subscription.id}/plan_change_preview", params: { plan_id: plan.id, strategy: strategy }, as: :json
  end

  it "previews an upgrade and applies it for exactly the previewed amount" do
    advance_days(10)
    preview(pro)
    shown = json

    expect(shown).to include("kind" => "upgrade", "allowed_strategies" => %w[immediate], "remaining_ratio" => "0.6774",
      "net_cents" => 3387, "amount_due_now_cents" => 3387)
    expect(shown["lines"].map { |line| line["amount_cents"] }).to eq([ -3319, 6706 ])

    post "/api/v1/subscriptions/#{subscription.id}/plan_changes", as: :json, headers: { "Idempotency-Key" => "change-1" },
      params: { plan_id: pro.id, strategy: "immediate", quote_token: shown["quote_token"], lock_version: subscription.reload.lock_version }

    expect(response).to have_http_status(:created)
    expect(json).to include("status" => "applied", "net_cents" => 3387)
    expect(Invoice.find(json["invoice_id"]).total_cents).to eq(3387)
  end

  it "answers 409 when the preview went stale" do
    preview(pro)
    quote_token = json["quote_token"]
    advance_days(31)

    post "/api/v1/subscriptions/#{subscription.id}/plan_changes", as: :json,
      params: { plan_id: pro.id, strategy: "immediate", quote_token: quote_token, lock_version: subscription.reload.lock_version }

    expect(response).to have_http_status(:conflict)
    expect(json.dig("error", "code")).to eq("stale_preview")
  end

  it "ignores a proration date chosen by the client and refuses a forged or mismatched token" do
    advance_days(10)
    lock = subscription.reload.lock_version

    # Backdating to the period start would change the amount; a raw date isn't accepted.
    post "/api/v1/subscriptions/#{subscription.id}/plan_changes", as: :json,
      params: { plan_id: pro.id, strategy: "immediate", proration_date: start.iso8601, lock_version: lock }
    expect(json.dig("error", "code")).to eq("quote_token_required")

    post "/api/v1/subscriptions/#{subscription.id}/plan_changes", as: :json,
      params: { plan_id: pro.id, strategy: "immediate", quote_token: "forged", lock_version: lock }
    expect(json.dig("error", "code")).to eq("invalid_quote_token")

    other_plan = create(:plan, name: "Max", amount_cents: 19_900, trial_days: 0)
    preview(other_plan)
    post "/api/v1/subscriptions/#{subscription.id}/plan_changes", as: :json,
      params: { plan_id: pro.id, strategy: "immediate", quote_token: json["quote_token"], lock_version: lock }
    expect(json.dig("error", "code")).to eq("invalid_quote_token")
    expect(subscription.plan_changes).to be_empty
  end

  it "answers 422 for a strategy the kind doesn't allow" do
    preview(pro, strategy: "at_period_end")

    expect(response).to have_http_status(:unprocessable_content)
    expect(json.dig("error", "details", "allowed")).to eq(%w[immediate])
  end

  it "schedules, lists and cancels a change" do
    Subscriptions::Create.call(customer: customer_with_card, plan: pro) # unrelated subscription
    downgrade_from = Subscriptions::Create.call(customer: customer_with_card, plan: pro).reload

    post "/api/v1/subscriptions/#{downgrade_from.id}/plan_changes", as: :json,
      params: { plan_id: basic.id, strategy: "at_period_end", lock_version: downgrade_from.lock_version }
    change_id = json["id"]

    get "/api/v1/subscriptions/#{downgrade_from.id}"
    expect(json["scheduled_plan_change"]).to include("id" => change_id, "status" => "scheduled")

    post "/api/v1/subscriptions/#{downgrade_from.id}/plan_changes/#{change_id}/cancel"
    expect(json["status"]).to eq("canceled")

    get "/api/v1/subscriptions/#{downgrade_from.id}/plan_changes"
    expect(json["data"].map { |change| change["status"] }).to eq(%w[canceled])
  end
end
