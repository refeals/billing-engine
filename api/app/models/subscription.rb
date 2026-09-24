class Subscription < ApplicationRecord
  class DirectStatusChangeError < StandardError; end

  belongs_to :customer
  belongs_to :plan
  has_many :state_transitions, -> { order(:occurred_at, :id) }, class_name: "SubscriptionStateTransition",
    dependent: :restrict_with_exception

  validates :provider_subscription_id, presence: true, uniqueness: true
  validates :status, inclusion: { in: SubscriptionStateMachine::STATES }
  validates :current_period_start, :current_period_end, presence: true

  # Status only changes through Subscriptions::Transition, which validates the move and
  # records it. Anything else changing it (a stray update, a console session) is a bug.
  before_update :refuse_direct_status_change

  scope :live, -> { where.not(status: "canceled") }
  scope :with_status, ->(status) { where(status: status) }
  scope :search, ->(query) {
    pattern = "%#{sanitize_sql_like(query.to_s.strip.downcase)}%"
    joins(:customer).where(
      "LOWER(customers.name) LIKE :pattern ESCAPE '\\' OR customers.email LIKE :pattern ESCAPE '\\'",
      pattern: pattern
    )
  }

  def audit_references
    { subscription_id: id, customer_id: customer_id }
  end

  def applying_transition
    @applying_transition = true
    yield
  ensure
    @applying_transition = false
  end

  # What an operator may do right now. The API refuses anything not listed here and the
  # frontend only renders buttons for these, so both always agree.
  def allowed_actions
    case status
    when "trialing" then cancellation_actions
    when "active" then cancellation_actions + (cancel_at_period_end? ? [] : %w[pause])
    when "past_due" then %w[cancel_now]
    when "paused" then %w[resume cancel_now]
    else []
    end
  end

  def action_allowed?(action)
    allowed_actions.include?(action)
  end

  private

  def cancellation_actions
    [ "cancel_now", cancel_at_period_end? ? "undo_cancel" : "cancel_at_period_end" ]
  end

  def refuse_direct_status_change
    return unless status_changed? && !@applying_transition

    raise DirectStatusChangeError, "Subscription status must change through Subscriptions::Transition"
  end
end
