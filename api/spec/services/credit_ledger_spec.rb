require "rails_helper"

RSpec.describe CreditLedger do
  let!(:customer) { create(:customer) }

  before { freeze_clock_at(Time.utc(2026, 10, 1)) }

  it "grants credit, keeping the cached balance equal to the ledger" do
    entry = described_class.credit!(customer, amount_cents: 1500, reason: "downgrade_proration")

    expect(entry).to have_attributes(amount_cents: 1500, balance_after_cents: 1500, occurred_at: Time.utc(2026, 10, 1))
    expect(customer.reload.credit_balance_cents).to eq(1500)
    expect(customer).to be_ledger_balance_matches
  end

  it "consumes credit with a negative entry" do
    described_class.credit!(customer, amount_cents: 1500, reason: "downgrade_proration")
    entry = described_class.debit!(customer, amount_cents: 400, reason: "applied_to_invoice")

    expect(entry).to have_attributes(amount_cents: -400, balance_after_cents: 1100)
    expect(customer.reload.credit_balance_cents).to eq(1100)
  end

  it "refuses to take the balance below zero and writes nothing" do
    described_class.credit!(customer, amount_cents: 1000, reason: "manual_adjustment")

    expect { described_class.debit!(customer, amount_cents: 1001, reason: "manual_adjustment") }
      .to raise_error(DomainError) { |error|
        expect(error.code).to eq("insufficient_credit")
        expect(error.details).to eq(balance_cents: 1000, requested_cents: 1001)
      }
    expect(customer.reload.credit_balance_cents).to eq(1000)
    expect(customer.credit_ledger_entries.count).to eq(1)
  end

  it "refuses a non-positive amount instead of flipping its sign" do
    [ -500, 0, "500" ].each do |amount|
      expect { described_class.credit!(customer, amount_cents: amount, reason: "manual_adjustment") }
        .to raise_error(ArgumentError)
      expect { described_class.debit!(customer, amount_cents: amount, reason: "manual_adjustment") }
        .to raise_error(ArgumentError)
    end
    expect(customer.credit_ledger_entries).to be_empty
  end

  it "rolls back the entry and the cache together when the caller fails" do
    ActiveRecord::Base.transaction do
      described_class.credit!(customer, amount_cents: 1000, reason: "manual_adjustment")
      raise ActiveRecord::Rollback
    end

    expect(customer.reload.credit_balance_cents).to eq(0)
    expect(customer.credit_ledger_entries).to be_empty
  end

  it "audits each movement with the balance before and after" do
    described_class.credit!(customer, amount_cents: 1000, reason: "manual_adjustment", note: "Goodwill")
    described_class.debit!(customer, amount_cents: 300, reason: "applied_to_invoice")

    granted, applied = BillingEvent.order(:id).to_a
    expect(granted).to have_attributes(event_type: "credit.granted", customer_id: customer.id)
    expect(granted.data).to include("after" => { "credit_balance_cents" => 1000 },
      "context" => { "reason" => "manual_adjustment", "amount_cents" => 1000, "note" => "Goodwill" })
    expect(applied.event_type).to eq("credit.applied")
  end
end
