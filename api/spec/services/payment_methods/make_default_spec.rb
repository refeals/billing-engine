require "rails_helper"

RSpec.describe PaymentMethods::MakeDefault do
  let(:customer) { create(:customer) }
  let!(:current_default) { create(:payment_method, customer: customer, is_default: true) }
  let!(:other) { create(:payment_method, customer: customer) }

  it "swaps the default without ever having two" do
    described_class.call(other)

    expect(customer.payment_methods.where(is_default: true)).to eq([ other ])
    expect(BillingEvent.of_type("payment_method.default_changed").count).to eq(1)
  end

  it "does nothing when the card is already the default" do
    described_class.call(current_default)

    expect(current_default.reload.is_default).to be(true)
    expect(BillingEvent.count).to eq(0)
  end
end
