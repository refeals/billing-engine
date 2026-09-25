require "rails_helper"

RSpec.describe "Reconciliation" do
  let(:start) { Time.utc(2026, 10, 1) }
  let(:outbox) { FakeStripe::MockedWebhookEvent }

  before { freeze_clock_at(start) }

  def run!(subscription = nil)
    Reconciliation::Run.call(triggered_by: "admin", subscription: subscription)
  end

  def open_kinds
    ReconciliationDiscrepancy.open.order(:id).pluck(:kind)
  end

  def resolve(kind, strategy, note: nil)
    Reconciliation::Resolve.call(ReconciliationDiscrepancy.open.find_by!(kind: kind), strategy: strategy, note: note)
  end

  # Runs the block without delivering anything, then loses the provider events of the given
  # type and delivers the rest: a webhook that never arrived.
  def losing(event_type)
    allow(FakeStripe::Dispatcher).to receive(:schedule_flush)
    yield
    outbox.pending.where(event_type: event_type).update_all(delivery_status: "dropped")
    allow(FakeStripe::Dispatcher).to receive(:schedule_flush).and_call_original
    FakeStripe::Dispatcher.flush
  end

  it "finds nothing when engine and provider went through the same history" do
    trial = subscribe(customer_with_card, trial_days: 3)
    upgraded = subscribe(customer_with_card, amount_cents: 2900)
    lost = subscribe(customer_with_card("pm_card_chargeDeclined"))
    advance_days(10)
    PlanChanges::Apply.call(upgraded.reload, lock_version: upgraded.lock_version, to_plan: create(:plan, amount_cents: 9900, trial_days: 0),
      strategy: "immediate", proration_date: BillingClock.now)
    Refunds::Create.call(trial.invoices.sole, amount_cents: 1000, destination: "original_method", reason: "service_issue")
    Refunds::Create.call(upgraded.invoices.first, amount_cents: 500, destination: "credit_balance", reason: "duplicate")
    advance_days(25)

    run = run!

    expect(lost.reload.status).to eq("canceled")
    expect(run).to have_attributes(subscriptions_checked: 3, discrepancies_found: 0)
    expect(ReconciliationDiscrepancy.count).to eq(0)
  end

  describe "a lost invoice.paid" do
    let!(:subscription) { subscribe(customer_with_card("pm_card_chargeDeclined")) }

    before do
      losing("invoice.paid") do
        PaymentMethods::Attach.call(subscription.customer, token: "pm_card_visa", exp_month: 12, exp_year: 2030, make_default: true)
      end
    end

    it "shows the missing event, the unpaid invoice and the wrong status, with evidence" do
      run!

      expect(open_kinds).to contain_exactly("undelivered_event", "invoice_status_mismatch", "status_mismatch")
      status = ReconciliationDiscrepancy.find_by!(kind: "status_mismatch")
      paid_event = outbox.find_by!(event_type: "invoice.paid")
      expect(status).to have_attributes(internal_value: "past_due", expected_value: "active", evidence_event_ids: [ paid_event.event_id ])
    end

    it "is fixed by redelivering the event, after which the next run clears the rest" do
      run!

      resolve("undelivered_event", "redeliver")
      expect(subscription.reload.status).to eq("active")

      run!
      expect(open_kinds).to be_empty
      expect(ReconciliationDiscrepancy.where(status: "cleared").pluck(:kind)).to contain_exactly("invoice_status_mismatch", "status_mismatch")
    end
  end

  it "reports a handler failure once, and reprocessing fixes it" do
    subscription = subscribe(customer_with_card)
    allow(Webhooks::Handlers::SubscriptionObserved).to receive(:call).and_raise("handler bug")
    Subscriptions::Pause.call(subscription.reload, lock_version: subscription.lock_version)
    allow(Webhooks::Handlers::SubscriptionObserved).to receive(:call).and_call_original

    run!
    expect(open_kinds).to eq(%w[failed_event])

    resolve("failed_event", "reprocess")
    run!
    expect(open_kinds).to be_empty
  end

  describe "a provider that disagrees" do
    let(:subscription) { subscribe(customer_with_card) }

    before do
      FakeStripe::Gateway.emit_subscription_event(subscription.provider_subscription_id,
        snapshot: subscription.reload.provider_snapshot.merge(status: "past_due"))
      run!
    end

    it "is fixed by telling the provider again (the engine is the authority)" do
      resolve("status_mismatch", "resync_provider")
      run!

      expect(open_kinds).to be_empty
      expect(subscription.reload.status).to eq("active")
    end

    it "can be corrected through the state machine, as a reconciliation correction" do
      resolve("status_mismatch", "apply_expected")

      transition = subscription.reload.state_transitions.last
      expect(transition).to have_attributes(to_status: "past_due", reason: "reconciliation_correction", actor_type: "reconciliation")
    end
  end

  it "refuses a correction the state machine doesn't allow, but lets the operator acknowledge it" do
    subscription = subscribe(customer_with_card)
    Subscriptions::Cancel.call(subscription.reload, lock_version: subscription.lock_version, at_period_end: false)
    FakeStripe::Gateway.emit_subscription_event(subscription.provider_subscription_id,
      snapshot: subscription.reload.provider_snapshot.merge(status: "active"))
    run!
    discrepancy = ReconciliationDiscrepancy.open.find_by!(kind: "status_mismatch")

    expect(discrepancy.available_resolutions).not_to include("apply_expected")
    expect { resolve("status_mismatch", "apply_expected") }
      .to raise_error(DomainError) { |error| expect(error.code).to eq("correction_not_allowed") }
    expect { resolve("status_mismatch", "acknowledge") }
      .to raise_error(DomainError) { |error| expect(error.code).to eq("note_required") }

    resolve("status_mismatch", "acknowledge", note: "Provider test data, ignore")
    expect(discrepancy.reload).to have_attributes(status: "acknowledged", resolution_note: "Provider test data, ignore")
    expect(subscription.reload.status).to eq("canceled")
  end

  it "catches a change the provider was never told about" do
    subscription = subscribe(customer_with_card)
    allow(FakeStripe::Gateway).to receive(:update_subscription).and_raise("provider unreachable")
    Subscriptions::Pause.call(subscription.reload, lock_version: subscription.lock_version)
    allow(FakeStripe::Gateway).to receive(:update_subscription).and_call_original

    run!
    expect(ReconciliationDiscrepancy.open.sole).to have_attributes(kind: "status_mismatch", internal_value: "paused", expected_value: "active")

    resolve("status_mismatch", "resync_provider")
    run!
    expect(open_kinds).to be_empty
  end

  it "doesn't reopen a difference the operator acknowledged, but reports a new value" do
    subscription = subscribe(customer_with_card)
    FakeStripe::Gateway.emit_subscription_event(subscription.provider_subscription_id,
      snapshot: subscription.reload.provider_snapshot.merge(status: "past_due"))
    run!
    resolve("status_mismatch", "acknowledge", note: "Known")

    2.times { run! }
    expect(ReconciliationDiscrepancy.where(kind: "status_mismatch").pluck(:status)).to eq(%w[acknowledged])

    FakeStripe::Gateway.emit_subscription_event(subscription.provider_subscription_id,
      snapshot: subscription.reload.provider_snapshot.merge(status: "paused"))
    run!
    expect(open_kinds).to eq(%w[status_mismatch])
  end

  it "asks to redeliver the lost event before correcting the status it caused" do
    subscription = subscribe(customer_with_card("pm_card_chargeDeclined"))
    losing("invoice.paid") do
      PaymentMethods::Attach.call(subscription.customer, token: "pm_card_visa", exp_month: 12, exp_year: 2030, make_default: true)
    end
    run!

    expect { resolve("status_mismatch", "apply_expected") }
      .to raise_error(DomainError) { |error| expect(error.message).to include("redeliver or reprocess it first") }
  end

  it "keeps the clock moving when the daily check fails" do
    subscribe(customer_with_card)
    allow(Reconciliation::Run).to receive(:call).and_raise("reconciliation bug")

    expect { advance_days(3) }.not_to raise_error
    expect(BillingClock.now).to eq(start + 3.days)
  end

  it "doesn't duplicate a discrepancy found again, and doesn't count events still in flight" do
    subscription = subscribe(customer_with_card)
    losing("customer.subscription.updated") { Subscriptions::Pause.call(subscription.reload, lock_version: subscription.lock_version) }

    2.times { run! }
    expect(ReconciliationDiscrepancy.where(kind: "undelivered_event").count).to eq(1)

    allow(FakeStripe::Dispatcher).to receive(:schedule_flush)
    Subscriptions::Resume.call(subscription.reload, lock_version: subscription.lock_version)
    expect(run!.discrepancies_opened).to eq(0)
  end
end
