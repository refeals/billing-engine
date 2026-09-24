require "rails_helper"

RSpec.describe "Subscription ticks" do
  let(:start) { Time.utc(2026, 10, 1) }

  before { freeze_clock_at(start) }

  def advance(days)
    BillingClock.advance!(days: days)
  end

  it "converts a trial when it ends (provisional until invoicing)" do
    subscription = Subscriptions::Create.call(customer: create(:customer), plan: create(:plan, trial_days: 3))

    report = advance(2)[:tick_report]
    expect(report[:trials_converted]).to eq(0)
    expect(subscription.reload.status).to eq("trialing")

    report = advance(1)[:tick_report]
    expect(report[:trials_converted]).to eq(1)
    expect(subscription.reload).to have_attributes(status: "active", current_period_start: start + 3.days,
      current_period_end: start + 3.days + 1.month)
    expect(subscription.state_transitions.last.actor_type).to eq("system_job")
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

  it "rolls an active period forward when it ends (provisional until invoicing)" do
    subscription = create(:subscription, current_period_start: start - 1.month + 1.day, current_period_end: start + 1.day)

    report = advance(1)[:tick_report]

    expect(report[:periods_renewed]).to eq(1)
    expect(subscription.reload).to have_attributes(current_period_start: start + 1.day,
      current_period_end: start + 1.day + 1.month)
    expect(BillingEvent.of_type("subscription.period_renewed").count).to eq(1)
  end

  it "catches up several missed periods at once" do
    subscription = create(:subscription, current_period_start: start - 3.months, current_period_end: start - 2.months)

    advance(1)

    expect(subscription.reload.current_period_end).to be > start + 1.day
    expect(subscription.current_period_start).to be <= start + 1.day
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
