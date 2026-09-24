module Subscriptions
  class UndoCancel < AdminAction
    def call
      with_guards("undo_cancel") do
        subscription.update!(cancel_at_period_end: false)
        Audit.record(event_type: "subscription.cancellation_revoked", subject: subscription,
          before: { cancel_at_period_end: true }, after: { cancel_at_period_end: false })
      end
    end
  end
end
