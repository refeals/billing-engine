class ReconciliationRunSerializer
  def initialize(run, detail: false)
    @run = run
    @detail = detail
  end

  def as_json(*)
    summary = @run.slice(:id, :triggered_by, :scope_subscription_id, :subscriptions_checked, :discrepancies_found,
      :discrepancies_opened, :discrepancies_cleared).merge(started_at: @run.started_at.iso8601, finished_at: @run.finished_at&.iso8601)
    return summary unless @detail

    discrepancies = @run.discrepancies_seen.includes(subscription: :customer).order(:id)
    summary.merge(discrepancies: discrepancies.map { |discrepancy| ReconciliationDiscrepancySerializer.new(discrepancy).as_json })
  end
end
