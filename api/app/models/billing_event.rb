class BillingEvent < ApplicationRecord
  include AppendOnly

  ACTOR_TYPES = %w[admin webhook system_job reconciliation].freeze

  belongs_to :subject, polymorphic: true, optional: true

  enum :actor_type, ACTOR_TYPES.index_by(&:itself), validate: true

  validates :event_type, presence: true, format: { with: /\A[a-z_]+\.[a-z_]+\z/ }
  validates :occurred_at, presence: true

  scope :for_subscription, ->(subscription_id) { where(subscription_id: subscription_id) }
  scope :for_customer, ->(customer_id) { where(customer_id: customer_id) }
  scope :of_type, ->(event_type) { where(event_type: event_type) }
  scope :by_actor, ->(actor_type) { where(actor_type: actor_type) }
  scope :occurred_from, ->(time) { where(occurred_at: time..) }
  scope :occurred_to, ->(time) { where(occurred_at: ..time) }
  scope :newest_first, -> { order(occurred_at: :desc, id: :desc) }
end
