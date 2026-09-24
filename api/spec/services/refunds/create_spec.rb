require "rails_helper"

RSpec.describe Refunds::Create do
  before { freeze_clock_at(Time.utc(2026, 10, 1)) }

  let(:outbox) { FakeStripe::MockedWebhookEvent }

  def paid_invoice(card: "pm_card_visa", amount_cents: 4900)
    subscribe(customer_with_card(card), amount_cents: amount_cents).invoices.sole.reload
  end

  def refund(invoice, amount_cents, destination: "original_method", reason: "requested_by_customer")
    described_class.call(invoice.reload, amount_cents: amount_cents, destination: destination, reason: reason)
  end

  it "refunds part of a card payment, settled by the provider's webhook" do
    invoice = paid_invoice

    refund = refund(invoice, 1500)

    # Pending at creation; the provider's refund.updated (delivered after commit) settles it.
    expect(refund.status).to eq("pending")
    expect(refund.reload).to have_attributes(status: "succeeded", provider_refund_id: start_with("re_"))
    expect(invoice.reload).to have_attributes(amount_refunded_cents: 1500, refundable_cents: 3400, status: "paid")
  end

  it "refunds up to the exact amount paid, and not one cent more" do
    invoice = paid_invoice
    refund(invoice, 3000)
    refund(invoice, 1900)

    expect(invoice.reload.refundable_cents).to eq(0)
    expect { refund(invoice, 1) }
      .to raise_error(DomainError) { |error|
        expect(error.code).to eq("refund_exceeds_refundable")
        expect(error.details).to eq(refundable_cents: 0, requested_cents: 1)
      }
  end

  it "counts pending refunds, so two quick requests can't both pass" do
    invoice = paid_invoice
    allow(FakeStripe::Dispatcher).to receive(:schedule_flush) # the provider hasn't answered yet

    refund(invoice, 4000)

    expect(invoice.reload.refunds.sole.status).to eq("pending")
    expect { refund(invoice, 1000) }.to raise_error(DomainError, /Only 900 cents/)
  end

  it "releases the amount of a refund that fails" do
    invoice = paid_invoice(card: "pm_card_refundFail")

    failed = refund(invoice, 4900).reload

    expect(failed).to have_attributes(status: "failed", failure_reason: "refund_failed")
    expect(invoice.reload).to have_attributes(amount_refunded_cents: 0, refundable_cents: 4900)
  end

  it "refunds to the credit balance at once, without the provider" do
    invoice = paid_invoice
    events_before = outbox.count

    refund = refund(invoice, 2000, destination: "credit_balance")

    expect(refund).to have_attributes(status: "succeeded", provider_refund_id: nil)
    expect(invoice.reload.amount_refunded_cents).to eq(2000)
    expect(invoice.customer.reload.credit_balance_cents).to eq(2000)
    expect(invoice.customer.credit_ledger_entries.last).to have_attributes(reason: "refund_to_balance", invoice_id: invoice.id)
    expect(outbox.count).to eq(events_before)
  end

  it "never touches the subscription, even for a full refund" do
    invoice = paid_invoice

    refund(invoice, 4900)

    expect(invoice.subscription.reload.status).to eq("active")
  end

  it "refuses an open invoice and one paid entirely with credit" do
    open_invoice = paid_invoice(card: "pm_card_chargeDeclined")
    expect { refund(open_invoice, 100) }.to raise_error(DomainError) { |error| expect(error.code).to eq("invoice_not_refundable") }

    customer = customer_with_card
    CreditLedger.credit!(customer, amount_cents: 10_000, reason: "manual_adjustment")
    covered = subscribe(customer).invoices.sole.reload
    expect(covered).to have_attributes(status: "paid", refundable_cents: 0)
    expect { refund(covered, 100) }.to raise_error(DomainError) { |error| expect(error.code).to eq("refund_exceeds_refundable") }
  end

  it "validates amount, destination and reason before reaching the provider" do
    invoice = paid_invoice
    events_before = outbox.count

    expect { refund(invoice, 0) }.to raise_error(DomainError) { |error| expect(error.code).to eq("invalid_amount") }
    expect { refund(invoice, 100, destination: "cash") }.to raise_error(DomainError) { |error| expect(error.code).to eq("invalid_refund") }
    expect(outbox.count).to eq(events_before)
  end

  it "counts a refund once even if its webhooks arrive again" do
    invoice = paid_invoice
    refund(invoice, 1500)

    %w[refund.updated charge.refunded].each do |type|
      FakeStripe::Dispatcher.redeliver(outbox.where(event_type: type).last)
    end

    expect(invoice.reload.amount_refunded_cents).to eq(1500)
    expect(BillingEvent.of_type("provider.charge_refunded").first.data.dig("context", "matches")).to be(true)
  end

  it "is also limited by the database and by the provider" do
    invoice = paid_invoice

    expect { invoice.update_columns(amount_refunded_cents: 5000) }.to raise_error(ActiveRecord::StatementInvalid, /CHECK/)

    charge = invoice.payment_attempts.sole.provider_charge_id
    FakeStripe::Gateway.refund(charge: charge, amount_cents: 4900, reason: "duplicate", payment_method: nil)
    FakeStripe::Gateway.refund(charge: charge, amount_cents: 1, reason: "duplicate", payment_method: nil)
    results = outbox.where(event_type: "refund.updated").map { |event| event.payload.dig("data", "object", "failure_reason") }
    expect(results).to eq([ nil, "amount_exceeds_charge" ])
  end
end
