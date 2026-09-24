require "rails_helper"

RSpec.describe Plan do
  it "is valid with the factory defaults" do
    expect(build(:plan)).to be_valid
  end

  it "rejects a non-integer amount instead of truncating it" do
    plan = build(:plan, amount_cents: "19.99")

    expect(plan).not_to be_valid
    expect(plan.errors[:amount_cents]).to include("must be an integer")
  end

  it "rejects unknown intervals, non-USD currencies and malformed codes" do
    expect(build(:plan, interval: "week")).not_to be_valid
    expect(build(:plan, currency: "BRL")).not_to be_valid
    expect(build(:plan, code: "Studio Pro")).not_to be_valid
  end

  it "enforces the amount and interval rules in the database too" do
    plan = build(:plan, amount_cents: 0, interval: "week")

    expect { plan.save!(validate: false) }.to raise_error(ActiveRecord::StatementInvalid, /CHECK constraint/)
  end

  describe "pricing is immutable once created" do
    let(:plan) { create(:plan) }

    it "raises when the price is reassigned" do
      expect { plan.amount_cents = 9900 }.to raise_error(ActiveRecord::ReadonlyAttributeError)
    end

    it "raises when the interval is reassigned" do
      expect { plan.interval = "year" }.to raise_error(ActiveRecord::ReadonlyAttributeError)
    end

    it "still allows renaming" do
      plan.update!(name: "Studio Plus")
      expect(plan.reload.name).to eq("Studio Plus")
    end
  end
end
