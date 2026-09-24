require "rails_helper"

RSpec.describe PaymentMethod do
  describe "#expired?" do
    let(:card) { build(:payment_method, exp_month: 10, exp_year: 2026) }

    it "is valid through the last moment of the expiry month" do
      expect(card.expired?(at: Time.utc(2026, 10, 31, 23, 59, 59))).to be(false)
    end

    it "expires as soon as the month is over" do
      expect(card.expired?(at: Time.utc(2026, 11, 1))).to be(true)
    end

    it "follows the simulated clock by default" do
      freeze_clock_at(Time.utc(2026, 10, 15))
      expect(card.expired?).to be(false)

      BillingClock.advance!(days: 17)
      expect(card.expired?).to be(true)
    end
  end

  it "derives its behavior from the test card token" do
    expect(build(:payment_method, test_card_token: "pm_card_chargeDeclinedInsufficientFunds").behavior)
      .to eq("insufficient_funds")
  end

  it "rejects a token that is not a known test card" do
    expect(build(:payment_method, test_card_token: "pm_card_unknown")).not_to be_valid
  end

  it "allows only one default card per customer, at the database level" do
    customer = create(:customer)
    create(:payment_method, customer: customer, is_default: true)

    expect { create(:payment_method, customer: customer, is_default: true) }
      .to raise_error(ActiveRecord::RecordNotUnique)
  end
end
