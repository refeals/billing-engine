class PaymentAttempt < ApplicationRecord
  include AppendOnly

  belongs_to :invoice
  belongs_to :payment_method, optional: true

  enum :status, %w[succeeded failed].index_by(&:itself), validate: true

  validates :provider_charge_id, presence: true, uniqueness: true
  validates :amount_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :attempted_at, presence: true
end
