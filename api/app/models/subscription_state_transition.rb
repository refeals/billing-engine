class SubscriptionStateTransition < ApplicationRecord
  include AppendOnly

  belongs_to :subscription
  belongs_to :billing_event

  validates :to_status, :reason, :actor_type, :occurred_at, presence: true
end
