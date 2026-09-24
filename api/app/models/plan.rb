class Plan < ApplicationRecord
  INTERVALS = %w[month year].freeze

  # Changing the price or interval of a plan in use would silently change what current
  # subscribers pay. A new plan is the explicit way to reprice; Rails raises on assignment.
  attr_readonly :code, :amount_cents, :currency, :interval

  validates :code, presence: true, uniqueness: true, format: { with: /\A[a-z0-9_]+\z/ }
  validates :name, presence: true
  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :currency, inclusion: { in: %w[USD] }
  validates :interval, inclusion: { in: INTERVALS }
  validates :trial_days, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }

  def archived?
    archived_at.present?
  end
end
