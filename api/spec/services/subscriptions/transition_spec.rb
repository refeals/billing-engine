require "rails_helper"

RSpec.describe Subscriptions::Transition do
  before { freeze_clock_at(Time.utc(2026, 10, 10, 9)) }

  let(:subscription) { create(:subscription) }

  it "changes the status and writes one transition row and one audit event" do
    described_class.call(subscription, to: "paused", reason: "customer_requested", attributes: { paused_at: BillingClock.now })

    transition = subscription.state_transitions.sole
    event = BillingEvent.of_type("subscription.transitioned").sole
    expect(subscription.reload.status).to eq("paused")
    expect(transition).to have_attributes(from_status: "active", to_status: "paused", reason: "customer_requested",
      actor_type: "admin", billing_event: event, occurred_at: Time.utc(2026, 10, 10, 9))
    expect(event.data).to include(
      "before" => { "status" => "active", "paused_at" => nil },
      "after" => { "status" => "paused", "paused_at" => "2026-10-10T09:00:00Z" },
      "context" => { "reason" => "customer_requested" }
    )
  end

  it "refuses a move the state machine doesn't allow and writes nothing" do
    expect { described_class.call(subscription, to: "trialing", reason: "customer_requested") }
      .to raise_error(InvalidTransitionError)
    expect(subscription.reload.status).to eq("active")
    expect(SubscriptionStateTransition.count + BillingEvent.count).to eq(0)
  end

  it "fails on a stale lock_version, leaving no history behind" do
    SubscriptionStateTransition # load before the concurrent edit
    Subscription.find(subscription.id).update!(cancel_at_period_end: true)

    expect { described_class.call(subscription, to: "paused", reason: "customer_requested") }
      .to raise_error(ActiveRecord::StaleObjectError)
    expect(SubscriptionStateTransition.count).to eq(0)
  end

  it "records creation as a move from nothing" do
    new_subscription = build(:subscription, :trialing)

    described_class.call(new_subscription, to: "trialing", reason: "subscription_created")

    expect(new_subscription.state_transitions.sole).to have_attributes(from_status: nil, to_status: "trialing")
  end
end
