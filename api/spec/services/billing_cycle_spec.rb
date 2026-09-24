require "rails_helper"

# The money cycle end to end: invoices are issued by the engine, charged by the fake
# provider, and settled only by the webhooks it sends back.
RSpec.describe "Billing cycle" do
  let(:start) { Time.utc(2026, 10, 1) }

  before { freeze_clock_at(start) }

  describe "trial end" do
    it "turns the trial active only when the provider reports the payment" do
      subscription = subscribe(customer_with_card, trial_days: 3)

      report = advance_days(3)

      invoice = subscription.invoices.sole
      expect(report[:trial_invoices_issued]).to eq(1)
      expect(invoice).to have_attributes(status: "paid", amount_paid_cents: 4900, period_start: start + 3.days)
      expect(subscription.reload).to have_attributes(status: "active", current_period_start: start + 3.days,
        current_period_end: start + 3.days + 1.month)
      transition = subscription.state_transitions.last
      expect(transition).to have_attributes(reason: "trial_converted", actor_type: "webhook")
      expect(transition.webhook_event_id).to eq(WebhookEvent.find_by!(event_type: "invoice.paid").id)
    end

    it "moves the trial to past_due when the card is declined" do
      subscription = subscribe(customer_with_card("pm_card_chargeDeclinedInsufficientFunds"), trial_days: 3)

      advance_days(3)

      expect(subscription.reload.status).to eq("past_due")
      expect(subscription.invoices.sole).to have_attributes(status: "open", amount_due_cents: 4900, attempt_count: 1)
      expect(subscription.invoices.sole.payment_attempts.sole)
        .to have_attributes(status: "failed", failure_code: "insufficient_funds")
    end

    it "fails the payment when there is no card at all" do
      subscription = subscribe(customer_with_card(nil), trial_days: 3)

      advance_days(3)

      expect(subscription.reload.status).to eq("past_due")
      expect(subscription.invoices.sole.payment_attempts.sole.failure_code).to eq("no_payment_method")
    end

    it "invoices a trial only once" do
      subscription = subscribe(customer_with_card("pm_card_chargeDeclined"), trial_days: 3)

      advance_days(10)

      expect(subscription.invoices.count).to eq(1)
    end
  end

  describe "creation without a trial" do
    it "bills the first period right away" do
      subscription = subscribe(customer_with_card, trial_days: 0)

      invoice = subscription.invoices.sole
      expect(invoice).to have_attributes(billing_reason: "subscription_create", status: "paid")
      expect(subscription.status).to eq("active")
    end

    it "goes past_due when that first payment fails" do
      subscription = subscribe(customer_with_card("pm_card_chargeDeclined"), trial_days: 0)

      expect(subscription.reload.status).to eq("past_due")
    end
  end

  describe "renewal" do
    it "bills each new period on the day the old one ends" do
      subscription = subscribe(customer_with_card, trial_days: 0)
      period_end = subscription.current_period_end
      days = ((period_end - start) / 1.day).ceil

      advance_days(days - 1)
      expect(subscription.invoices.count).to eq(1)

      report = advance_days(1)
      expect(report[:renewal_invoices_issued]).to eq(1)
      expect(subscription.invoices.order(:id).last).to have_attributes(period_start: period_end, status: "paid")
      expect(subscription.reload.current_period_start).to eq(period_end)
    end

    it "charges an expired card no more: the renewal fails with expired_card" do
      subscription = subscribe(customer_with_card("pm_card_visa", exp_month: 10, exp_year: 2026), trial_days: 0)

      advance_days(31)

      expect(subscription.reload.status).to eq("past_due")
      expect(subscription.invoices.order(:id).last.payment_attempts.sole.failure_code).to eq("expired_card")
    end

    it "doesn't renew past_due, paused or scheduled-to-cancel subscriptions" do
      past_due = subscribe(customer_with_card("pm_card_chargeDeclined"), trial_days: 0)
      paused = subscribe(customer_with_card, trial_days: 0)
      Subscriptions::Pause.call(paused, lock_version: paused.reload.lock_version)
      canceling = subscribe(customer_with_card, trial_days: 0)
      Subscriptions::Cancel.call(canceling, lock_version: canceling.reload.lock_version, at_period_end: true)

      advance_days(32)

      expect([ past_due, paused, canceling ].map { |subscription| subscription.invoices.count }).to eq([ 1, 1, 1 ])
      expect(canceling.reload.status).to eq("canceled")
    end
  end

  describe "recovery" do
    it "recovers a past_due subscription when a retried payment goes through" do
      customer = customer_with_card("pm_card_chargeDeclined")
      subscription = subscribe(customer, trial_days: 0)
      PaymentMethods::Attach.call(customer, token: "pm_card_visa", exp_month: 12, exp_year: 2030, make_default: true)

      Invoices::RequestPayment.call(subscription.invoices.sole)

      expect(subscription.reload.status).to eq("active")
      expect(subscription.state_transitions.last.reason).to eq("payment_recovered")
      expect(subscription.invoices.sole.payment_attempts.map(&:status)).to eq(%w[failed succeeded])
    end

    it "lets a card that succeeds after failures eventually pay" do
      subscription = subscribe(customer_with_card("pm_card_succeedsAfterFailures_2"), trial_days: 0)
      invoice = subscription.invoices.sole

      2.times { Invoices::RequestPayment.call(invoice) }

      expect(invoice.reload).to have_attributes(status: "paid", attempt_count: 3)
      expect(invoice.payment_attempts.map(&:status)).to eq(%w[failed failed succeeded])
    end
  end

  describe "pause and billing" do
    it "never bills the time spent paused" do
      subscription = subscribe(customer_with_card, trial_days: 0)
      Subscriptions::Pause.call(subscription, lock_version: subscription.reload.lock_version)

      advance_days(60)
      expect(subscription.invoices.count).to eq(1)

      Subscriptions::Resume.call(subscription, lock_version: subscription.reload.lock_version)

      resumed_invoice = subscription.invoices.order(:id).last
      expect(subscription.invoices.count).to eq(2)
      expect(resumed_invoice.period_start).to eq(start + 60.days)
      expect(subscription.reload).to have_attributes(status: "active", current_period_start: start + 60.days)
    end

    it "continues an already-paid period when the pause ends before it" do
      subscription = subscribe(customer_with_card, trial_days: 0)
      period_end = subscription.current_period_end
      Subscriptions::Pause.call(subscription, lock_version: subscription.reload.lock_version)
      advance_days(5)

      Subscriptions::Resume.call(subscription, lock_version: subscription.reload.lock_version)

      expect(subscription.invoices.count).to eq(1)
      expect(subscription.reload.current_period_end).to eq(period_end)
    end
  end

  it "doesn't report events emitted during a tick as retries" do
    3.times { subscribe(customer_with_card, trial_days: 1) }

    report = advance_days(1)

    expect(report[:trial_invoices_issued]).to eq(3)
    expect(report[:provider_deliveries_retried]).to eq(0)
    expect(FakeStripe::MockedWebhookEvent.pending).to be_empty
  end

  describe "the same charge reported by two events" do
    it "records one payment attempt" do
      subscription = subscribe(customer_with_card, trial_days: 0)

      expect(WebhookEvent.where(event_type: %w[charge.succeeded invoice.paid]).count).to eq(2)
      expect(subscription.invoices.sole.payment_attempts.count).to eq(1)
    end
  end

  describe "a late failure report" do
    it "can't undo a payment" do
      subscription = subscribe(customer_with_card, trial_days: 0)
      invoice = subscription.invoices.sole
      stale_failure = stripe_event(type: "invoice.payment_failed", created: start - 1.day, object: {
        id: invoice.provider_invoice_id, charge: "ch_old", amount_due: 4900, attempt_count: 1,
        last_payment_error: { code: "card_declined" }
      })

      expect(ingest(stale_failure).status).to eq(:skipped_stale)
      expect(invoice.reload.status).to eq("paid")
      expect(subscription.reload.status).to eq("active")
    end
  end
end
