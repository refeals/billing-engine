class Subscription < ApplicationRecord
  class DirectStatusChangeError < StandardError; end

  belongs_to :customer
  belongs_to :plan
  has_many :invoices, dependent: :restrict_with_exception
  has_many :plan_changes, dependent: :restrict_with_exception
  has_many :state_transitions, -> { order(:occurred_at, :id) }, class_name: "SubscriptionStateTransition",
    dependent: :restrict_with_exception

  validates :provider_subscription_id, presence: true, uniqueness: true
  validates :status, inclusion: { in: SubscriptionStateMachine::STATES }
  validates :current_period_start, :current_period_end, presence: true

  # Status only changes through Subscriptions::Transition, which validates the move and
  # records it. Anything else changing it (a stray update, a console session) is a bug.
  before_update :refuse_direct_status_change

  # Every committed change is pushed to the provider, after commit so the provider never
  # hears about something we rolled back. Living on the model means no new service can
  # forget it. Webhook observation uses update_columns, which skips this, so an event the
  # provider sends us is never echoed back to it.
  after_commit :push_to_provider, on: :update

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

  # Plain values only: the provider must not depend on reading our records.
  def provider_snapshot
    {
      customer: customer.provider_customer_id,
      plan: plan.code,
      status: status,
      current_period_start: current_period_start,
      current_period_end: current_period_end,
      trial_end: trial_ends_at,
      cancel_at_period_end: cancel_at_period_end,
      canceled_at: canceled_at
    }
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
    when "trialing" then cancellation_actions + plan_change_actions
    when "active" then cancellation_actions + (cancel_at_period_end? ? [] : %w[pause change_plan])
    when "past_due" then %w[cancel_now]
    when "paused" then %w[resume cancel_now]
    else []
    end
  end

  # Suspension only means something while the subscription is past_due and payable. Once it
  # is canceled (by dunning or otherwise), access is gone for good, whatever the column says;
  # the column is kept as history.
  def access_suspended?
    status == "past_due" && access_suspended_at.present?
  end

  def action_allowed?(action)
    allowed_actions.include?(action)
  end

  private

  # Runs after our change committed, so failing here can't undo it; raising would only turn a
  # successful operation into a 500. The failure is recorded instead, and the provider stays
  # behind until the next change or until reconciliation flags the difference.
  def push_to_provider
    PaymentGateway.current.update_subscription(provider_subscription_id, snapshot: provider_snapshot)
  rescue StandardError => error
    Rails.error.report(error, handled: true, context: { subscription_id: id })
    ActiveRecord::Base.transaction do
      Audit.record(event_type: "provider.sync_failed", subject: self, actor: Current.actor || "system_job",
        context: { error: error.class.name, message: error.message.truncate(500), status: status })
    end
  end

  # Changing plans on a subscription that is about to end would be meaningless; the operator
  # undoes the cancellation first.
  def plan_change_actions
    cancel_at_period_end? ? [] : %w[change_plan]
  end

  def cancellation_actions
    [ "cancel_now", cancel_at_period_end? ? "undo_cancel" : "cancel_at_period_end" ]
  end

  def refuse_direct_status_change
    return unless status_changed? && !@applying_transition

    raise DirectStatusChangeError, "Subscription status must change through Subscriptions::Transition"
  end
end
