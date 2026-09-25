require "rails_helper"

# The failed-payment schedule end to end: failure (day 0), retry (day 3), suspension (day 7),
# cancellation (day 14), and every way out of it.
RSpec.describe "Dunning" do
  let(:start) { Time.utc(2026, 10, 1) }

  before { freeze_clock_at(start) }

  def failing_subscription(card = "pm_card_chargeDeclined")
    subscribe(customer_with_card(card)).reload
  end

  def steps_by_day(dunning_case)
    dunning_case.reload.steps.map { |step| [ step.step, ((step.executed_at - start) / 1.day).round ] }
  end

  it "runs each step on its day and cancels on day 14" do
    subscription = failing_subscription
    dunning_case = DunningCase.sole

    expect(dunning_case).to have_attributes(status: "open", invoice: subscription.invoices.sole, next_step: "day_3_retry")
    14.times { advance_days(1) }

    expect(steps_by_day(dunning_case)).to eq([
      [ "day_0_notice", 0 ], [ "day_3_retry", 3 ], [ "day_7_suspend", 7 ], [ "day_14_cancel", 14 ]
    ])
    expect(dunning_case).to have_attributes(status: "exhausted", closed_reason: "dunning_exhausted")
    expect(subscription.reload).to have_attributes(status: "canceled", cancellation_reason: "dunning_exhausted")
    # Access is simply gone now; "suspended" (and its "pay to restore" promise) no longer applies.
    expect(subscription.access_suspended?).to be(false)
    expect(subscription.invoices.sole.status).to eq("uncollectible")
    expect(CustomerNotification.pluck(:kind)).to eq(%w[payment_failed payment_retry access_suspended subscription_canceled])
  end

  it "gets the same result when the 14 days are advanced in one call" do
    subscription = failing_subscription

    advance_days(14)

    expect(steps_by_day(DunningCase.sole).map(&:last)).to eq([ 0, 3, 7, 14 ])
    expect(subscription.reload.status).to eq("canceled")
  end

  it "links the day-3 retry attempt to its step, and a failed retry keeps the same case" do
    subscription = failing_subscription

    advance_days(3)

    retry_step = DunningStep.find_by!(step: "day_3_retry")
    retry_attempt = subscription.invoices.sole.payment_attempts.last
    expect(retry_attempt).to have_attributes(status: "failed", dunning_case_id: retry_step.dunning_case_id,
      dunning_step_id: retry_step.id)
    expect(DunningCase.count).to eq(1)
    expect(DunningCase.sole.next_step).to eq("day_7_suspend")
  end

  it "recovers when the customer adds a working card, and skips the remaining steps" do
    subscription = failing_subscription
    advance_days(4)

    PaymentMethods::Attach.call(subscription.customer, token: "pm_card_visa", exp_month: 12, exp_year: 2030, make_default: true)
    advance_days(10)

    dunning_case = DunningCase.sole
    expect(dunning_case).to have_attributes(status: "recovered", closed_reason: "payment_received")
    expect(steps_by_day(dunning_case)).to eq([ [ "day_0_notice", 0 ], [ "day_3_retry", 3 ] ])
    expect(subscription.reload.status).to eq("active")
    card_retry = subscription.invoices.sole.payment_attempts.last
    expect(card_retry).to have_attributes(status: "succeeded", dunning_case_id: dunning_case.id, dunning_step_id: nil)
    expect(CustomerNotification.last.kind).to eq("payment_recovered")
  end

  it "restores access when payment arrives after the suspension" do
    subscription = failing_subscription
    advance_days(8)
    expect(subscription.reload.access_suspended_at).to eq(start + 7.days)

    PaymentMethods::Attach.call(subscription.customer, token: "pm_card_visa", exp_month: 12, exp_year: 2030, make_default: true)

    expect(subscription.reload).to have_attributes(status: "active", access_suspended_at: nil)
    expect(BillingEvent.of_type("subscription.access_restored").count).to eq(1)
  end

  it "recovers on the day-3 retry for a card that succeeds after failures" do
    subscription = failing_subscription("pm_card_succeedsAfterFailures_2")
    # The creation charge was failure #1; a card update retry would be #2. Day 3 is #2 here.
    advance_days(3)
    expect(subscription.reload.status).to eq("past_due")

    advance_days(4)
    expect(DunningCase.sole.status).to eq("open")
    Invoices::RequestPayment.call(subscription.invoices.sole)

    expect(DunningCase.sole.status).to eq("recovered")
    expect(subscription.reload.status).to eq("active")
  end

  it "doesn't repeat a step if the job runs twice" do
    failing_subscription
    advance_days(3)
    dunning_case = DunningCase.sole

    result = Dunning::RunStep.call(dunning_case, "day_3_retry", at: BillingClock.now)

    expect(result).to be_nil
    expect(dunning_case.steps.where(step: "day_3_retry").count).to eq(1)
    expect(CustomerNotification.where(kind: "payment_retry").count).to eq(1)
  end

  it "closes the case, but keeps the invoice owed, when the operator cancels during dunning" do
    subscription = failing_subscription
    advance_days(2)

    Subscriptions::Cancel.call(subscription.reload, lock_version: subscription.lock_version, at_period_end: false)

    expect(DunningCase.sole).to have_attributes(status: "canceled", closed_reason: "subscription_canceled")
    expect(subscription.invoices.sole.status).to eq("open")
    advance_days(14)
    expect(DunningStep.count).to eq(1)
  end

  it "makes an exhausted invoice impossible to retry or refund" do
    subscription = failing_subscription
    advance_days(14)
    invoice = subscription.invoices.sole.reload
    events_before = FakeStripe::MockedWebhookEvent.count

    expect(invoice).to have_attributes(status: "uncollectible", refundable_cents: 0)
    expect(invoice.open_for_payment?).to be(false)
    # Even a direct payment request is refused by the service itself.
    Invoices::RequestPayment.call(invoice)
    expect(FakeStripe::MockedWebhookEvent.count).to eq(events_before)
  end

  it "never asks the provider to collect a paid invoice again" do
    invoice = subscribe(customer_with_card).invoices.sole.reload
    events_before = FakeStripe::MockedWebhookEvent.count

    expect(Invoices::RequestPayment.call(invoice)).to be_nil
    expect(FakeStripe::MockedWebhookEvent.count).to eq(events_before)
  end

  it "no longer lets a past_due subscription linger past a monthly period" do
    subscription = failing_subscription

    advance_days(40)

    expect(subscription.reload.status).to eq("canceled")
    expect(subscription.invoices.count).to eq(1)
  end
end
