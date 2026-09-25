require "rails_helper"

RSpec.describe Dashboard::Summary do
  before { freeze_clock_at(Time.utc(2026, 10, 1, 9)) }

  describe "MRR" do
    let(:monthly) { create(:plan, amount_cents: 5_900, interval: "month") }
    let(:yearly) { create(:plan, amount_cents: 59_000, interval: "year") }

    it "counts active and past_due subscriptions only, yearly plans divided by 12" do
      create(:subscription, plan: monthly, status: "active")
      create(:subscription, plan: monthly, status: "past_due")
      create(:subscription, plan: monthly, status: "active", cancel_at_period_end: true)
      create(:subscription, :trialing, plan: monthly)
      create(:subscription, :paused, plan: monthly)
      create(:subscription, plan: monthly, status: "canceled", canceled_at: Time.utc(2026, 10, 1))
      create(:subscription, plan: yearly, status: "active")

      summary = described_class.call

      expect(summary[:mrr_cents]).to eq(3 * 5_900 + 4_917)
      expect(summary[:paying_subscriptions]).to eq(4)
    end

    it "rounds each yearly subscription on its own, so MRR is the sum of what each shows" do
      create_list(:subscription, 2, plan: yearly, status: "active")

      expect(described_class.call[:mrr_cents]).to eq(2 * 4_917) # not round(118_000 / 12) = 9_833
    end
  end

  it "lists every status, including the ones with no subscription" do
    create(:subscription, status: "active")

    expect(described_class.call[:subscriptions_by_status])
      .to eq("trialing" => 0, "active" => 1, "past_due" => 0, "paused" => 0, "canceled" => 0)
  end

  it "reports open dunning cases with the amount their invoices still owe" do
    plans = Demo::Catalog.ensure!
    Current.set(actor: "admin") do
      customer = Customers::Create.call(name: "Declined Studio", email: "declined@example.test")
      PaymentMethods::Attach.call(customer, token: "pm_card_visa", exp_month: 12, exp_year: 2030, make_default: true)
      subscription = Subscriptions::Create.call(customer: customer.reload, plan: plans.fetch("studio"))
      PaymentMethods::Attach.call(customer.reload, token: "pm_card_chargeDeclined", exp_month: 12, exp_year: 2030, make_default: true)
      BillingClock.advance!(days: 30)
      BillingClock.advance!(days: 1) # October has 31 days; the renewal runs on Nov 1
    end

    dunning = described_class.call[:dunning]

    expect(dunning).to eq(open_cases: 1, amount_at_risk_cents: 5_900, by_step: { "day_0_notice" => 1 })
  end

  it "shows the ten newest audit events" do
    Current.set(actor: "admin") do
      ApplicationRecord.transaction do
        12.times { |index| Audit.record(event_type: "clock.advanced", context: { index: index }) }
      end
    end

    events = described_class.call[:recent_events]

    expect(events.size).to eq(10)
    expect(events.pluck(:id)).to eq(BillingEvent.order(id: :desc).limit(10).ids)
  end
end
