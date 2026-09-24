require "rails_helper"

RSpec.describe PaymentMethods::Attach do
  let(:customer) { create(:customer) }

  before { freeze_clock_at(Time.utc(2026, 10, 15)) }

  def attach(token: "pm_card_visa", exp_month: 12, exp_year: 2028, make_default: false)
    described_class.call(customer, token: token, exp_month: exp_month, exp_year: exp_year, make_default: make_default)
  end

  it "copies the card details from the test card catalog" do
    card = attach(token: "pm_card_chargeDeclinedInsufficientFunds")

    expect(card).to have_attributes(brand: "visa", last4: "9995", test_card_token: "pm_card_chargeDeclinedInsufficientFunds")
    expect(card.provider_payment_method_id).to start_with("pm_")
  end

  it "makes the first card the default so renewals always have a card to charge" do
    expect(attach.is_default).to be(true)
    expect(attach.is_default).to be(false)
  end

  it "moves the default when asked" do
    first = attach
    second = attach(make_default: true)

    expect(first.reload.is_default).to be(false)
    expect(second.is_default).to be(true)
  end

  it "refuses a card that has already expired, like Stripe does" do
    expect { attach(exp_month: 9, exp_year: 2026) }
      .to raise_error(DomainError) { |error| expect(error.code).to eq("card_expired") }
    expect(customer.payment_methods).to be_empty
  end

  it "accepts a card that expires at the end of the current month" do
    expect(attach(exp_month: 10, exp_year: 2026)).to be_persisted
  end

  it "refuses an unknown token" do
    expect { attach(token: "pm_card_unknown") }
      .to raise_error(DomainError) { |error| expect(error.code).to eq("unknown_test_card") }
  end

  it "audits the attachment" do
    card = attach

    expect(BillingEvent.of_type("payment_method.attached").sole).to have_attributes(subject: card, customer_id: customer.id)
  end
end
