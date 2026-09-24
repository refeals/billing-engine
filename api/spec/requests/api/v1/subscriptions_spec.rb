require "rails_helper"

RSpec.describe "Subscriptions", type: :request do
  let(:now) { Time.utc(2026, 10, 10) }
  let(:customer) { create(:customer, name: "Studio Flow", email: "hello@flow.test") }
  let(:plan) { create(:plan, trial_days: 14) }

  before { freeze_clock_at(now) }

  def json
    response.parsed_body
  end

  def post_action(subscription, action, **body)
    post "/api/v1/subscriptions/#{subscription.id}/#{action}", params: body, as: :json
  end

  it "creates a trialing subscription" do
    post "/api/v1/subscriptions", params: { customer_id: customer.id, plan_id: plan.id }, as: :json

    expect(response).to have_http_status(:created)
    expect(json).to include("status" => "trialing", "trial_ends_at" => (now + 14.days).iso8601,
      "allowed_actions" => %w[cancel_now cancel_at_period_end change_plan], "lock_version" => 0)
    expect(json["customer"]).to eq("id" => customer.id, "name" => "Studio Flow", "email" => "hello@flow.test")
  end

  it "filters by status and searches by customer" do
    active = create(:subscription, customer: customer)
    create(:subscription, :paused)

    get "/api/v1/subscriptions", params: { status: "active" }
    expect(json["data"].map { |row| row["id"] }).to eq([ active.id ])

    get "/api/v1/subscriptions", params: { q: "hello@flow" }
    expect(json["data"].map { |row| row["id"] }).to eq([ active.id ])
  end

  it "rejects an unknown status filter" do
    get "/api/v1/subscriptions", params: { status: "zombie" }
    expect(json.dig("error", "code")).to eq("invalid_filter")
  end

  it "pauses and resumes, returning the new state and actions" do
    subscription = create(:subscription)

    post_action(subscription, :pause, lock_version: 0, resumes_at: "2026-10-20")
    expect(json).to include("status" => "paused", "resumes_at" => "2026-10-20T00:00:00Z", "allowed_actions" => %w[resume cancel_now])

    post_action(subscription, :resume, lock_version: json["lock_version"])
    expect(json["status"]).to eq("active")
  end

  it "answers 409 when the operator acted on an outdated screen" do
    subscription = create(:subscription)
    Subscriptions::Cancel.call(subscription, lock_version: 0, at_period_end: true)

    post_action(subscription, :cancel, lock_version: 0, at_period_end: false)

    expect(response).to have_http_status(:conflict)
    expect(subscription.reload.status).to eq("active")
  end

  it "answers 422 for an action the current state doesn't allow" do
    subscription = create(:subscription, status: "canceled")

    post_action(subscription, :resume, lock_version: 0)

    expect(response).to have_http_status(:unprocessable_content)
    expect(json.dig("error", "code")).to eq("action_not_allowed")
  end

  it "requires lock_version" do
    post_action(create(:subscription), :cancel, at_period_end: true)
    expect(response).to have_http_status(:bad_request)
  end

  it "lists the state transitions in order" do
    post "/api/v1/subscriptions", params: { customer_id: customer.id, plan_id: plan.id }, as: :json
    id = json["id"]
    post "/api/v1/subscriptions/#{id}/cancel", params: { lock_version: json["lock_version"] }, as: :json

    get "/api/v1/subscriptions/#{id}/state_transitions"

    expect(json["data"].map { |row| [ row["from_status"], row["to_status"], row["reason"] ] }).to eq([
      [ nil, "trialing", "subscription_created" ],
      [ "trialing", "canceled", "customer_requested" ]
    ])
  end

  it "shows the customer's subscriptions on the customer" do
    subscription = create(:subscription, customer: customer)

    get "/api/v1/customers/#{customer.id}"

    expect(json["subscriptions"].sole).to include("id" => subscription.id, "status" => "active")
  end

  describe "idempotency keys" do
    let(:subscription) { create(:subscription) }

    def cancel_with_key(key, **body)
      post "/api/v1/subscriptions/#{subscription.id}/cancel", params: { lock_version: 0, **body }, as: :json,
        headers: { "Idempotency-Key" => key }
    end

    it "replays the first response for a retried request" do
      cancel_with_key("key-1", at_period_end: true)
      first = json

      cancel_with_key("key-1", at_period_end: true)

      expect(response).to have_http_status(:ok)
      expect(response.headers["Idempotent-Replayed"]).to eq("true")
      expect(json).to eq(first)
      expect(BillingEvent.of_type("subscription.cancellation_scheduled").count).to eq(1)
    end

    context "when the first response was an error" do
      let(:subscription) { create(:subscription, cancel_at_period_end: true) }

      it "replays the error too" do
        2.times { cancel_with_key("key-2", at_period_end: true) }

        expect(response).to have_http_status(:unprocessable_content)
        expect(json.dig("error", "code")).to eq("action_not_allowed")
        expect(response.headers["Idempotent-Replayed"]).to eq("true")
      end
    end

    it "refuses the same key for a different request" do
      cancel_with_key("key-3", at_period_end: true)
      cancel_with_key("key-3", at_period_end: false)

      expect(response).to have_http_status(:conflict)
      expect(json.dig("error", "code")).to eq("idempotency_key_reused")
    end

    it "refuses a key whose first request is still running" do
      path = "/api/v1/subscriptions/#{subscription.id}/cancel"
      body = { lock_version: 0, at_period_end: true }.to_json
      IdempotencyKey.create!(key: "key-4", request_fingerprint: Digest::SHA256.hexdigest([ "POST", path, body ].join("\n")))

      cancel_with_key("key-4", at_period_end: true)

      expect(response).to have_http_status(:conflict)
      expect(json.dig("error", "code")).to eq("idempotency_key_in_progress")
    end

    it "does not keep the key when the request crashes, so a retry can run" do
      allow(Subscriptions::Cancel).to receive(:call).and_raise(RuntimeError, "boom")

      expect { cancel_with_key("key-5", at_period_end: true) }.to raise_error(RuntimeError, "boom")
      expect(IdempotencyKey.where(key: "key-5")).to be_empty
    end
  end
end
