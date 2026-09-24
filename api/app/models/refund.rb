class Refund < ApplicationRecord
  DESTINATIONS = %w[original_method credit_balance].freeze
  REASONS = %w[requested_by_customer duplicate fraudulent service_issue].freeze

  belongs_to :invoice
  belongs_to :payment_attempt, optional: true

  enum :status, %w[pending succeeded failed].index_by(&:itself), validate: true
  enum :destination, DESTINATIONS.index_by(&:itself), validate: true, prefix: :to
  enum :reason, REASONS.index_by(&:itself), validate: true, prefix: :because

  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :requested_at, presence: true

  # Refunds that hold part of the refundable amount: done, or on their way. A failed one
  # releases its amount.
  scope :counting, -> { where(status: %w[pending succeeded]) }
  scope :newest_first, -> { order(id: :desc) }

  def audit_references
    invoice.audit_references
  end
end
