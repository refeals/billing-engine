require "rails_helper"

RSpec.describe "Subscription ticks" do
  let(:start) { Time.utc(2026, 10, 1) }

  before { freeze_clock_at(start) }

  def advance(days)
    BillingClock.advance!(days: days)
  end

  it "cancels a trial scheduled to cancel instead of converting it" do
    subscription = Subscriptions::Create.call(customer: create(:customer), plan: create(:plan, trial_days: 3))
    Subscriptions::Cancel.call(subscription, lock_version: subscription.lock_version, at_period_end: true)

    advance(3)

    expect(subscription.reload).to have_attributes(status: "canceled", canceled_at: start + 3.days,
      cancellation_reason: "period_ended_after_cancel_request")
  end

  it "cancels an active subscription at the end of its period" do
    subscription = create(:subscription, current_period_start: start, current_period_end: start + 2.days,
      cancel_at_period_end: true)

    advance(1)
    expect(subscription.reload.status).to eq("active")

    advance(1)
    expect(subscription.reload.status).to eq("canceled")
  end

  it "ends a timed pause on its resume date" do
    subscription = create(:subscription, :paused, resumes_at: start + 2.days)

    advance(1)
    expect(subscription.reload.status).to eq("paused")

    report = advance(1)[:tick_report]
    expect(report[:subscriptions_resumed]).to eq(1)
    expect(subscription.reload.state_transitions.last).to have_attributes(to_status: "active", reason: "pause_ended")
  end

  it "doesn't renew a subscription scheduled to cancel; it cancels it" do
    subscription = create(:subscription, current_period_end: start + 1.day, cancel_at_period_end: true)

    advance(1)

    expect(subscription.reload).to have_attributes(status: "canceled", canceled_at: start + 1.day)
  end

  it "leaves an open-ended pause alone" do
    subscription = create(:subscription, :paused, resumes_at: nil)

    advance(30)

    expect(subscription.reload.status).to eq("paused")
  end
end
