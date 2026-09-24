class Invoice < ApplicationRecord
  STATUSES = %w[open paid void uncollectible].freeze
  BILLING_REASONS = %w[subscription_create subscription_cycle subscription_update manual].freeze

  belongs_to :subscription
  belongs_to :customer
  has_many :line_items, -> { order(:id) }, class_name: "InvoiceLineItem", dependent: :restrict_with_exception
  has_many :payment_attempts, -> { order(:attempted_at, :id) }, dependent: :restrict_with_exception

  # Once issued, what the invoice asks for is fixed: corrections are new documents (credit,
  # refunds), never edits. Only the settlement fields (paid, refunded, due, status) move.
  attr_readonly :number, :provider_invoice_id, :billing_reason, :period_start, :period_end,
    :subtotal_cents, :credit_applied_cents, :total_cents, :currency

  enum :status, STATUSES.index_by(&:itself), validate: true
  enum :billing_reason, BILLING_REASONS.index_by(&:itself), validate: true, prefix: :billed_for

  validates :number, :provider_invoice_id, :period_start, :period_end, :issued_at, presence: true
  validates :subtotal_cents, :credit_applied_cents, :amount_paid_cents, :amount_due_cents,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :newest_first, -> { order(issued_at: :desc, id: :desc) }

  def audit_references
    { subscription_id: subscription_id, customer_id: customer_id }
  end

  def open_for_payment?
    open? && amount_due_cents.positive?
  end
end
