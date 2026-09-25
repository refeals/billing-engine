class DunningCaseSerializer
  def initialize(dunning_case, detail: false)
    @dunning_case = dunning_case
    @detail = detail
  end

  def as_json(*)
    dunning_case = @dunning_case
    invoice = dunning_case.invoice
    summary = {
      id: dunning_case.id,
      status: dunning_case.status,
      started_at: dunning_case.started_at.iso8601,
      last_step: dunning_case.last_step,
      next_step: dunning_case.next_step,
      next_step_at: dunning_case.next_step_at&.iso8601,
      closed_at: dunning_case.closed_at&.iso8601,
      closed_reason: dunning_case.closed_reason,
      subscription_id: dunning_case.subscription_id,
      access_suspended: dunning_case.subscription.access_suspended?,
      customer: dunning_case.subscription.customer.slice(:id, :name, :email),
      invoice: { id: invoice.id, number: invoice.number, total_cents: invoice.total_cents,
        amount_due_cents: invoice.amount_due_cents, status: invoice.status }
    }
    return summary unless @detail

    summary.merge(
      steps: dunning_case.steps.map { |step| step.slice(:id, :step, :outcome).merge(scheduled_at: step.scheduled_at.iso8601, executed_at: step.executed_at.iso8601) },
      notifications: dunning_case.notifications.map { |notification| CustomerNotificationSerializer.new(notification).as_json },
      payment_attempts: PaymentAttempt.where(dunning_case_id: dunning_case.id).order(:attempted_at, :id).map do |attempt|
        PaymentAttemptSerializer.new(attempt).as_json.merge(dunning_step_id: attempt.dunning_step_id)
      end
    )
  end
end
