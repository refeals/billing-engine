require "rails_helper"

RSpec.describe CreditLedgerEntry do
  let(:customer) { create(:customer) }

  def build_entry(**attributes)
    described_class.new(customer: customer, amount_cents: 500, balance_after_cents: 500,
      reason: "manual_adjustment", occurred_at: Time.utc(2026, 10, 1), **attributes)
  end

  it "only lets each reason move the balance in its own direction" do
    expect(build_entry(reason: "downgrade_proration", amount_cents: -500)).not_to be_valid
    expect(build_entry(reason: "applied_to_invoice", amount_cents: 500)).not_to be_valid
    expect(build_entry(reason: "manual_adjustment", amount_cents: -500)).to be_valid
  end

  it "rejects a zero amount" do
    expect(build_entry(amount_cents: 0)).not_to be_valid
  end

  it "is append-only in the database" do
    entry = build_entry.tap(&:save!)

    expect { described_class.where(id: entry.id).update_all(amount_cents: 1) }
      .to raise_error(ActiveRecord::StatementInvalid, /credit_ledger_entries is append-only/)
    expect { described_class.where(id: entry.id).delete_all }
      .to raise_error(ActiveRecord::StatementInvalid, /credit_ledger_entries is append-only/)
  end
end
