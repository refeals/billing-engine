require "rails_helper"

# The seeds replay 70 simulated days, so they run once for all examples, outside the
# per-example transaction, and wipe the database afterwards.
RSpec.describe Demo::Seed do
  before(:all) { @summary = described_class.call }
  after(:all) { Demo::Reset.call(reseed: false) }

  it "ends with every subscription status and every dunning stage represented" do
    expect(@summary).to include(
      simulated_now: "2026-03-16T09:00:00Z",
      customers: 20,
      subscriptions: { "active" => 12, "canceled" => 2, "past_due" => 3, "paused" => 1, "trialing" => 2 },
      open_dunning_cases: { "day_0_notice" => 1, "day_3_retry" => 1, "day_7_suspend" => 1 },
      refunds: { "credit_balance" => 1, "original_method" => 1 }
    )
    expect(@summary[:invoices]).to include("uncollectible" => 1)
    expect(@summary[:customers_with_credit]).to eq(1)
  end

  it "reconciles to zero differences, since everything went through the real services" do
    expect(@summary[:open_discrepancies]).to eq(0)
    expect(Reconciliation::Run.call(triggered_by: "admin").discrepancies_found).to eq(0)
  end

  it "gives the dashboard the same figures" do
    dashboard = Dashboard::Summary.call

    expect(dashboard[:subscriptions_by_status]).to eq(@summary[:subscriptions])
    expect(dashboard[:dunning]).to include(open_cases: 3, by_step: @summary[:open_dunning_cases])
    expect(dashboard[:dunning][:amount_at_risk_cents]).to be_positive
    expect(dashboard[:paying_subscriptions]).to eq(15)
    expect(dashboard[:mrr_cents]).to eq(89_517)
  end

  it "leaves the audit trail and the ledger consistent" do
    created = BillingEvent.of_type("subscription.transitioned").where("json_extract(data, '$.context.reason') = 'subscription_created'")
    expect(created.distinct.count(:subscription_id)).to eq(Subscription.count)
    expect(Customer.all).to all(be_ledger_balance_matches)
  end
end
