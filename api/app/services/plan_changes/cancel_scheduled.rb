module PlanChanges
  # Drops a change that was waiting for renewal: replaced by a newer one, removed by the
  # operator, or left behind by a subscription that was canceled.
  class CancelScheduled < ApplicationService
    def initialize(plan_change, reason:)
      @plan_change = plan_change
      @reason = reason
    end

    def call
      unless @plan_change.scheduled?
        raise DomainError.new("This plan change is already #{@plan_change.status}", code: "plan_change_not_scheduled")
      end

      ActiveRecord::Base.transaction do
        @plan_change.update!(status: "canceled")
        Audit.record(event_type: "plan.change_canceled", subject: @plan_change,
          before: { status: "scheduled" }, after: { status: "canceled" },
          context: { reason: @reason, to_plan: @plan_change.to_plan.code })
        @plan_change
      end
    end
  end
end
