class PaymentMethod < ApplicationRecord
  belongs_to :customer

  validates :provider_payment_method_id, presence: true, uniqueness: true
  validates :test_card_token, inclusion: { in: ->(_) { FakeStripe::TestCards::CATALOG.keys } }
  validates :brand, :last4, presence: true
  validates :exp_month, numericality: { only_integer: true, in: 1..12 }
  validates :exp_year, numericality: { only_integer: true, greater_than: 2000 }

  # Cards are valid through the last moment of their expiry month. Because the clock can be
  # fast-forwarded, a card can expire in the middle of a subscription.
  def expired?(at: BillingClock.now)
    at > expires_at
  end

  def expires_at
    Time.utc(exp_year, exp_month).end_of_month
  end

  def behavior
    FakeStripe::TestCards.fetch(test_card_token).behavior
  end
end
