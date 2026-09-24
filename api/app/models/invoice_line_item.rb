class InvoiceLineItem < ApplicationRecord
  include AppendOnly

  KINDS = %w[subscription proration_credit proration_charge credit_applied].freeze

  belongs_to :invoice
  belongs_to :plan, optional: true

  enum :kind, KINDS.index_by(&:itself), validate: true

  validates :description, presence: true
  validates :amount_cents, numericality: { only_integer: true }
end
