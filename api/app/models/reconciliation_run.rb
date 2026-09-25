class ReconciliationRun < ApplicationRecord
  belongs_to :scope_subscription, class_name: "Subscription", optional: true
  has_many :discrepancies_seen, class_name: "ReconciliationDiscrepancy", foreign_key: :last_seen_run_id,
    inverse_of: :last_seen_run, dependent: :restrict_with_exception

  validates :triggered_by, :started_at, presence: true

  scope :newest_first, -> { order(id: :desc) }
end
