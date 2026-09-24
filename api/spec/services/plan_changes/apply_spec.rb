require "rails_helper"

RSpec.describe PlanChanges::Apply do
  let(:start) { Time.utc(2026, 10, 1) }
  let(:basic) { create(:plan, code: "basic", name: "Basic", amount_cents: 4900, trial_days: 0) }
  let(:pro) { create(:plan, code: "pro", name: "Pro", amount_cents: 9900, trial_days: 0) }

  before { freeze_clock_at(start) }

  def active_subscription(plan: basic, card: "pm_card_visa")
    Subscriptions::Create.call(customer: customer_with_card(card), plan: plan).reload
  end

  def quote(subscription, to_plan, strategy: nil)
    PlanChanges::Quote.new(subscription: subscription.reload, to_plan: to_plan, strategy: strategy)
  end

  def apply(subscription, to_plan, strategy: "immediate", proration_date: nil)
    subscription.reload
    proration_date ||= quote(subscription, to_plan, strategy: strategy).proration_date&.iso8601
    described_class.call(subscription, lock_version: subscription.lock_version, to_plan: to_plan,
      strategy: strategy, proration_date: proration_date)
  end

  describe "an upgrade" do
    it "charges exactly what the preview showed, through a proration invoice" do
      subscription = active_subscription
      advance_days(10)
      preview = quote(subscription, pro)

      plan_change = apply(subscription, pro)

      invoice = plan_change.invoice.reload
      expect(preview).to have_attributes(kind: "upgrade", credit_cents: -3319, charge_cents: 6706, net_cents: 3387,
        amount_due_now_cents: 3387)
      expect(invoice).to have_attributes(billing_reason: "subscription_update", subtotal_cents: 3387,
        total_cents: 3387, status: "paid", period_start: start + 10.days)
      expect(invoice.line_items.map { |line| [ line.kind, line.amount_cents ] })
        .to eq([ [ "proration_credit", -3319 ], [ "proration_charge", 6706 ] ])
      expect(subscription.reload.plan).to eq(pro)
      expect(subscription.current_period_start).to eq(start)
    end

    it "keeps the new plan and goes past_due when the proration payment fails" do
      subscription = active_subscription(card: "pm_card_succeedsAfterFailures_2")
      # The first charge (at creation) failed once already; the proration charge fails again.
      Invoices::RequestPayment.call(subscription.invoices.sole) until subscription.invoices.sole.reload.paid?
      customer = subscription.customer
      PaymentMethods::Attach.call(customer, token: "pm_card_chargeDeclined", exp_month: 12, exp_year: 2030, make_default: true)
      advance_days(5)

      plan_change = apply(subscription, pro)

      expect(plan_change.invoice.reload.status).to eq("open")
      expect(subscription.reload).to have_attributes(status: "past_due", plan: pro)
    end

    it "spends the customer's credit before charging the proration" do
      subscription = active_subscription
      CreditLedger.credit!(subscription.customer, amount_cents: 1000, reason: "manual_adjustment")
      advance_days(10)

      invoice = apply(subscription, pro).invoice.reload

      expect(invoice).to have_attributes(subtotal_cents: 3387, credit_applied_cents: 1000, total_cents: 2387)
    end

    it "can't be scheduled for later" do
      subscription = active_subscription

      expect { quote(subscription, pro, strategy: "at_period_end") }
        .to raise_error(DomainError) { |error| expect(error.code).to eq("strategy_not_allowed") }
    end
  end

  describe "a downgrade" do
    it "turns the unused difference into credit, spent by the next renewal" do
      subscription = active_subscription(plan: pro)
      advance_days(10)

      plan_change = apply(subscription, basic)

      customer = subscription.customer.reload
      expect(plan_change).to have_attributes(kind: "downgrade", net_cents: -3387, invoice: nil)
      expect(customer.credit_balance_cents).to eq(3387)
      expect(customer.credit_ledger_entries.last).to have_attributes(reason: "downgrade_proration", plan_change_id: plan_change.id)

      advance_days(21)

      renewal = subscription.invoices.order(:id).last
      expect(renewal).to have_attributes(billing_reason: "subscription_cycle", subtotal_cents: 4900,
        credit_applied_cents: 3387, total_cents: 1513, status: "paid")
      expect(customer.reload.credit_balance_cents).to eq(0)
    end

    it "can wait for the renewal, then bills the new price" do
      subscription = active_subscription(plan: pro)
      advance_days(10)

      plan_change = apply(subscription, basic, strategy: "at_period_end")

      expect(plan_change).to have_attributes(status: "scheduled", effective_at: start + 31.days)
      expect(subscription.reload.plan).to eq(pro)

      advance_days(21)

      expect(plan_change.reload.status).to eq("applied")
      expect(subscription.reload.plan).to eq(basic)
      expect(subscription.invoices.order(:id).last).to have_attributes(subtotal_cents: 4900, period_start: start + 31.days)
    end

    it "replaces a previously scheduled change" do
      subscription = active_subscription(plan: pro)
      standard = create(:plan, code: "standard", name: "Standard", amount_cents: 6900, trial_days: 0)
      first = apply(subscription, basic, strategy: "at_period_end")

      second = apply(subscription, standard, strategy: "at_period_end")

      expect(first.reload.status).to eq("canceled")
      expect(second.status).to eq("scheduled")
    end
  end

  it "swaps the plan during a trial without moving money, and the trial ends on the new price" do
    subscription = Subscriptions::Create.call(customer: customer_with_card, plan: create(:plan, trial_days: 5, amount_cents: 4900))

    plan_change = apply(subscription, pro)

    expect(plan_change).to have_attributes(kind: "trial_swap", net_cents: 0, invoice: nil)
    advance_days(5)
    expect(subscription.invoices.sole.subtotal_cents).to eq(9900)
  end

  it "handles two changes in the same cycle, each prorated from the plan in effect" do
    subscription = active_subscription
    advance_days(10)
    apply(subscription, pro)
    advance_days(10)

    second = apply(subscription, basic)

    expect(second).to have_attributes(kind: "downgrade", credit_cents: -3513, charge_cents: 1739, net_cents: -1774)
  end

  describe "the preview's date" do
    it "gives the same amount after the clock moves inside the period" do
      subscription = active_subscription
      advance_days(10)
      preview = quote(subscription, pro)
      advance_days(2)

      plan_change = apply(subscription, pro, proration_date: preview.proration_date.iso8601)

      expect(plan_change.net_cents).to eq(preview.net_cents)
    end

    it "is refused once the period has been renewed" do
      subscription = active_subscription
      preview = quote(subscription, pro)
      advance_days(31)

      expect { apply(subscription, pro, proration_date: preview.proration_date.iso8601) }
        .to raise_error(DomainError) { |error|
          expect(error.code).to eq("stale_preview")
          expect(error.http_status).to eq(:conflict)
        }
    end

    it "(through its signed token) is required for a prorated change" do
      subscription = active_subscription.reload

      expect {
        described_class.call(subscription, lock_version: subscription.lock_version, to_plan: pro, strategy: "immediate")
      }.to raise_error(DomainError) { |error| expect(error.code).to eq("quote_token_required") }
    end
  end

  describe "refusals" do
    it "refuses a past_due, paused or cancel-scheduled subscription" do
      past_due = active_subscription(card: "pm_card_chargeDeclined")
      expect { quote(past_due, pro) }.to raise_error(DomainError) { |error| expect(error.code).to eq("action_not_allowed") }

      canceling = active_subscription
      Subscriptions::Cancel.call(canceling, lock_version: canceling.reload.lock_version, at_period_end: true)
      expect { quote(canceling, pro) }.to raise_error(DomainError) { |error| expect(error.code).to eq("action_not_allowed") }
    end

    it "refuses the same plan, an archived plan and an interval change" do
      subscription = active_subscription
      yearly = create(:plan, interval: "year", amount_cents: 49_000)
      archived = create(:plan, archived_at: start)

      [ [ basic, "same_plan" ], [ archived, "plan_archived" ], [ yearly, "interval_change_not_supported" ] ].each do |plan, code|
        expect { quote(subscription, plan) }.to raise_error(DomainError) { |error| expect(error.code).to eq(code) }
      end
    end

    it "refuses a stale lock_version" do
      subscription = active_subscription
      stale = subscription.lock_version
      Subscriptions::Pause.call(subscription, lock_version: stale)
      Subscriptions::Resume.call(subscription, lock_version: subscription.reload.lock_version)

      expect {
        described_class.call(subscription, lock_version: stale, to_plan: pro, strategy: "immediate",
          proration_date: BillingClock.now.iso8601)
      }.to raise_error(ActiveRecord::StaleObjectError)
    end
  end

  describe "scheduled changes" do
    it "can be canceled" do
      subscription = active_subscription(plan: pro)
      plan_change = apply(subscription, basic, strategy: "at_period_end")

      PlanChanges::CancelScheduled.call(plan_change, reason: "operator_canceled")

      expect(plan_change.reload.status).to eq("canceled")
      expect { PlanChanges::CancelScheduled.call(plan_change, reason: "again") }
        .to raise_error(DomainError) { |error| expect(error.code).to eq("plan_change_not_scheduled") }
    end

    it "are dropped when the subscription is canceled" do
      subscription = active_subscription(plan: pro)
      plan_change = apply(subscription, basic, strategy: "at_period_end")

      Subscriptions::Cancel.call(subscription, lock_version: subscription.reload.lock_version, at_period_end: false)

      expect(plan_change.reload.status).to eq("canceled")
      expect(BillingEvent.of_type("plan.change_canceled").sole.data.dig("context", "reason")).to eq("subscription_canceled")
    end
  end
end
