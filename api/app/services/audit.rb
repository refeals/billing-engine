# The single write path for the audit trail.
module Audit
  class OutsideTransactionError < StandardError; end

  # Records an event in the caller's transaction, so the business change and its audit
  # row commit or roll back together. Calling it outside a transaction is a bug (half of
  # the story could be written), so it raises instead of opening one silently.
  def self.record(event_type:, subject: nil, before: nil, after: nil, context: {}, actor: Current.actor)
    # RSpec wraps each example in a non-joinable fixture transaction, so checking for a
    # joinable one catches the missing wrapper in tests too.
    unless BillingEvent.lease_connection.current_transaction.joinable?
      raise OutsideTransactionError, "Audit.record must run inside the caller's transaction"
    end
    raise ArgumentError, "Audit.record needs an actor (set Current.actor)" if actor.blank?

    references = subject&.audit_references || {}

    BillingEvent.create!(
      event_type: event_type,
      actor_type: actor,
      subject: subject,
      subscription_id: references[:subscription_id],
      customer_id: references[:customer_id],
      data: { before: before, after: after, context: context }.compact_blank,
      occurred_at: BillingClock.now
    )
  end
end
