class PlanChange < ApplicationRecord
  KINDS = %w[upgrade downgrade lateral trial_swap].freeze
  STRATEGIES = %w[immediate at_period_end].freeze
  STATUSES = %w[scheduled applied canceled].freeze

  belongs_to :subscription
  belongs_to :from_plan, class_name: "Plan"
  belongs_to :to_plan, class_name: "Plan"
  belongs_to :invoice, optional: true

  enum :kind, KINDS.index_by(&:itself), validate: true
  enum :strategy, STRATEGIES.index_by(&:itself), validate: true, prefix: :strategy
  enum :status, STATUSES.index_by(&:itself), validate: true

  validates :effective_at, presence: true
  validates :credit_cents, :charge_cents, :net_cents, numericality: { only_integer: true }

  scope :newest_first, -> { order(id: :desc) }

  def audit_references
    { subscription_id: subscription_id, customer_id: subscription.customer_id }
  end
end
