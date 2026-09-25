class ReconciliationDiscrepancy < ApplicationRecord
  KINDS = %w[status_mismatch plan_mismatch period_mismatch missing_invoice invoice_status_mismatch
    invoice_amount_mismatch undelivered_event failed_event].freeze

  # How each kind can be dealt with. Anything that fixes the engine goes through the inbox or
  # the state machine, never around them; invoice differences are fixed by redelivering the
  # event behind them, after which the next run clears them.
  RESOLUTIONS = {
    "undelivered_event" => %w[redeliver acknowledge],
    "failed_event" => %w[reprocess acknowledge],
    "status_mismatch" => %w[apply_expected resync_provider acknowledge],
    "plan_mismatch" => %w[resync_provider acknowledge],
    "period_mismatch" => %w[resync_provider acknowledge]
  }.freeze

  belongs_to :subscription
  belongs_to :first_run, class_name: "ReconciliationRun"
  belongs_to :last_seen_run, class_name: "ReconciliationRun"

  enum :kind, KINDS.index_by(&:itself), validate: true
  enum :status, %w[open resolved acknowledged cleared].index_by(&:itself), validate: true

  scope :newest_first, -> { order(id: :desc) }

  def available_resolutions
    return [] unless open?

    RESOLUTIONS.fetch(kind, %w[acknowledge]) - blocked_resolutions.keys
  end

  # Resolutions that exist for this kind but can't apply right now, with the reason, so the
  # screen can explain a disabled button instead of hiding it.
  def blocked_resolutions
    return {} unless open? && status_mismatch?

    if !correction_allowed?
      { "apply_expected" => "The subscription can't move from #{subscription.status} to #{expected_value}; " \
                            "the state machine has no such transition." }
    elsif pending_event_discrepancies?
      # The status is a symptom: fixing it directly would leave the invoice, the dunning case
      # and the audit trail behind. Redelivering the event fixes all of them together.
      { "apply_expected" => "A lost or failed event for this subscription is still open; redeliver or reprocess it first." }
    else
      {}
    end
  end

  def pending_event_discrepancies?
    ReconciliationDiscrepancy.open.where(subscription_id: subscription_id, kind: %w[undelivered_event failed_event]).exists?
  end

  def correction_allowed?
    SubscriptionStateMachine.allowed?(subscription.status, expected_value, SubscriptionStateMachine::RECONCILIATION_REASON)
  end

  def audit_references
    { subscription_id: subscription_id, customer_id: subscription.customer_id }
  end
end
