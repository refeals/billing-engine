require "rails_helper"

RSpec.describe Subscriptions::Create do
  let(:now) { Time.utc(2026, 10, 10) }
  let(:customer) { create(:customer) }

  before { freeze_clock_at(now) }

  it "starts a trial whose period is the trial itself" do
    subscription = described_class.call(customer: customer, plan: create(:plan, trial_days: 14))

    expect(subscription).to have_attributes(status: "trialing", current_period_start: now,
      current_period_end: now + 14.days, trial_ends_at: now + 14.days)
    expect(subscription.provider_subscription_id).to start_with("sub_")
  end

  it "starts active for a plan without a trial" do
    subscription = described_class.call(customer: customer, plan: create(:plan, trial_days: 0, interval: "year"))

    expect(subscription).to have_attributes(status: "active", trial_ends_at: nil, current_period_end: now + 1.year)
  end

  it "refuses an archived plan" do
    plan = create(:plan, archived_at: now)

    expect { described_class.call(customer: customer, plan: plan) }
      .to raise_error(DomainError) { |error| expect(error.code).to eq("plan_archived") }
  end

  it "refuses a second live subscription for the same customer" do
    described_class.call(customer: customer, plan: create(:plan))

    expect { described_class.call(customer: customer, plan: create(:plan)) }
      .to raise_error(DomainError) { |error| expect(error.code).to eq("customer_already_subscribed") }
  end
end
