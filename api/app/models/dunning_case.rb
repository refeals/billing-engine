class DunningCase < ApplicationRecord
  STATUSES = %w[open recovered exhausted canceled].freeze

  belongs_to :subscription
  belongs_to :invoice
  has_many :steps, -> { order(:executed_at, :id) }, class_name: "DunningStep", dependent: :restrict_with_exception
  has_many :notifications, -> { order(:sent_at, :id) }, class_name: "CustomerNotification", dependent: :restrict_with_exception
  has_many :payment_attempts, -> { order(:attempted_at, :id) }, inverse_of: false

  enum :status, STATUSES.index_by(&:itself), validate: true

  validates :started_at, presence: true

  scope :newest_first, -> { order(started_at: :desc, id: :desc) }

  def audit_references
    { subscription_id: subscription_id, customer_id: subscription.customer_id }
  end
end
