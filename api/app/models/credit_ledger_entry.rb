class CreditLedgerEntry < ApplicationRecord
  include AppendOnly

  # Which direction each reason may move the balance. A downgrade can only grant credit and
  # paying an invoice can only consume it; only a manual adjustment goes both ways.
  REASON_DIRECTIONS = {
    "downgrade_proration" => :credit,
    "refund_to_balance" => :credit,
    "applied_to_invoice" => :debit,
    "manual_adjustment" => :either
  }.freeze

  belongs_to :customer

  enum :reason, REASON_DIRECTIONS.keys.index_by(&:itself), validate: true

  validates :amount_cents, numericality: { only_integer: true, other_than: 0 }
  validates :balance_after_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :occurred_at, presence: true
  validate :amount_matches_reason_direction

  scope :newest_first, -> { order(id: :desc) }

  private

  def amount_matches_reason_direction
    direction = REASON_DIRECTIONS[reason]
    return if direction.nil? || direction == :either || amount_cents.nil?

    expected_positive = direction == :credit
    errors.add(:amount_cents, "must be #{expected_positive ? 'positive' : 'negative'} for #{reason}") if amount_cents.positive? != expected_positive
  end
end
