require "rails_helper"

RSpec.describe Invoices::Issue do
  let(:start) { Time.utc(2026, 10, 1) }

  before { freeze_clock_at(start) }

  def issue(subscription)
    described_class.call(subscription: subscription, billing_reason: "subscription_cycle",
      period_start: start, period_end: start + 1.month)
  end

  it "issues an open invoice with a subscription line, a number and a provider id" do
    subscription = subscribe(customer_with_card, trial_days: 14)

    invoice = issue(subscription)

    # Born open; it becomes paid only when the provider's webhook arrives, after commit.
    expect(invoice).to have_attributes(number: "BE-2026-000001", status: "open", subtotal_cents: 4900,
      credit_applied_cents: 0, total_cents: 4900, billing_reason: "subscription_cycle")
    expect(invoice.reload.status).to eq("paid")
    expect(invoice.provider_invoice_id).to start_with("in_")
    expect(invoice.line_items.sole).to have_attributes(kind: "subscription", amount_cents: 4900)
    expect(BillingEvent.of_type("invoice.issued").sole.subject).to eq(invoice)
  end

  it "spends credit before charging the card" do
    customer = customer_with_card
    CreditLedger.credit!(customer, amount_cents: 1500, reason: "manual_adjustment")
    subscription = subscribe(customer, trial_days: 14)

    invoice = issue(subscription).reload

    expect(invoice).to have_attributes(credit_applied_cents: 1500, total_cents: 3400, amount_paid_cents: 3400)
    expect(invoice.line_items.map { |line| [ line.kind, line.amount_cents ] })
      .to eq([ [ "subscription", 4900 ], [ "credit_applied", -1500 ] ])
    expect(customer.reload.credit_balance_cents).to eq(0)
    expect(customer.credit_ledger_entries.last).to have_attributes(reason: "applied_to_invoice", invoice_id: invoice.id)
  end

  it "settles an invoice fully covered by credit without a charge, still through the provider" do
    customer = customer_with_card
    CreditLedger.credit!(customer, amount_cents: 10_000, reason: "manual_adjustment")
    subscription = subscribe(customer, trial_days: 14)

    invoice = issue(subscription).reload

    expect(invoice).to have_attributes(total_cents: 0, status: "paid", amount_paid_cents: 0)
    expect(invoice.payment_attempts).to be_empty
    expect(customer.reload.credit_balance_cents).to eq(5100)
    expect(WebhookEvent.find_by(provider_object_id: invoice.provider_invoice_id, event_type: "invoice.paid")).to be_present
  end

  it "freezes the amounts once issued" do
    invoice = issue(subscribe(customer_with_card, trial_days: 14))

    expect { invoice.subtotal_cents = 1 }.to raise_error(ActiveRecord::ReadonlyAttributeError)
    expect { invoice.line_items.first.update!(amount_cents: 1) }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it "keeps the total consistent at the database level" do
    invoice = issue(subscribe(customer_with_card, trial_days: 14))

    expect { Invoice.where(id: invoice.id).update_all(total_cents: 1) }
      .to raise_error(ActiveRecord::StatementInvalid, /CHECK constraint/)
  end
end
