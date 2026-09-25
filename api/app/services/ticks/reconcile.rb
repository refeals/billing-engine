module Ticks
  # A full reconciliation for every simulated day. It runs once the day has committed, not
  # inside it: until then the engine has changed (a renewed period, a dunning cancellation)
  # but hasn't told the provider yet, and comparing that half-finished picture would report
  # differences that disappear a moment later.
  class Reconcile
    def self.call(at:)
      ActiveRecord.after_all_transactions_commit do
        Reconciliation::Run.call(triggered_by: "system_job")
      rescue StandardError => error
        # A failed check must never stop time: the day already committed, and the next days
        # still have work to do. The error is reported and the next run tries again.
        Rails.error.report(error, handled: true, context: { tick: "reconcile", at: at.iso8601 })
      end
      {}
    end
  end
end
