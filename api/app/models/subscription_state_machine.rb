# Every status a subscription can have and every move between them, with the reasons that
# justify each move. Written out as data so the whole lifecycle can be read (and tested)
# in one place; `nil` as origin means "being created".
module SubscriptionStateMachine
  STATES = %w[trialing active past_due paused canceled].freeze

  TRANSITIONS = {
    nil => {
      "trialing" => %w[subscription_created],
      "active" => %w[subscription_created]
    },
    "trialing" => {
      "active" => %w[trial_converted],
      "past_due" => %w[payment_failed],
      "canceled" => %w[customer_requested period_ended_after_cancel_request]
    },
    "active" => {
      "past_due" => %w[payment_failed],
      "paused" => %w[customer_requested],
      "canceled" => %w[customer_requested period_ended_after_cancel_request]
    },
    "past_due" => {
      "active" => %w[payment_recovered],
      "canceled" => %w[dunning_exhausted customer_requested period_ended_after_cancel_request]
    },
    "paused" => {
      "active" => %w[customer_requested pause_ended],
      "canceled" => %w[customer_requested]
    },
    "canceled" => {}
  }.transform_values { |targets| targets.transform_values(&:freeze).freeze }.freeze

  # Reconciliation may correct a status along any existing edge, but never opens a new one.
  RECONCILIATION_REASON = "reconciliation_correction"

  module_function

  def targets_from(from)
    TRANSITIONS.fetch(from, {})
  end

  def allowed?(from, to, reason)
    reasons = targets_from(from)[to]
    return false if reasons.nil?

    reasons.include?(reason) || reason == RECONCILIATION_REASON
  end

  def assert!(from, to, reason)
    return if allowed?(from, to, reason)

    raise InvalidTransitionError.new(
      "Cannot move a subscription from #{from || 'nothing'} to #{to} (#{reason})",
      details: { from: from, to: to, reason: reason, allowed: targets_from(from) }
    )
  end
end
