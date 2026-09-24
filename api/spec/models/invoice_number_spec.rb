require "rails_helper"

RSpec.describe InvoiceNumber do
  def next_number(year)
    ActiveRecord::Base.transaction { described_class.next!(year) }
  end

  it "numbers invoices sequentially within a year" do
    expect([ next_number(2026), next_number(2026), next_number(2026) ])
      .to eq(%w[BE-2026-000001 BE-2026-000002 BE-2026-000003])
  end

  it "starts again at 1 each year" do
    next_number(2026)

    expect(next_number(2027)).to eq("BE-2027-000001")
  end

  it "gives the number back when the invoice's transaction rolls back, leaving no gap" do
    next_number(2026)
    ActiveRecord::Base.transaction do
      described_class.next!(2026)
      raise ActiveRecord::Rollback
    end

    expect(next_number(2026)).to eq("BE-2026-000002")
  end

  it "refuses to hand out a number outside a transaction" do
    expect { described_class.next!(2026) }.to raise_error(Audit::OutsideTransactionError)
  end
end
