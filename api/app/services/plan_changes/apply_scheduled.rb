module PlanChanges
  # Carries out a change scheduled for renewal: the new period simply starts on the new
  # plan, so there is nothing to prorate.
  class ApplyScheduled < ApplicationService
    def initialize(plan_change)
      @plan_change = plan_change
    end

    def call
      ActiveRecord::Base.transaction do
        subscription = @plan_change.subscription
        subscription.update!(plan: @plan_change.to_plan)
        @plan_change.update!(status: "applied")
        Audit.record(event_type: "plan.changed", subject: @plan_change,
          before: { plan: @plan_change.from_plan.code, amount_cents: @plan_change.from_plan.amount_cents },
          after: { plan: @plan_change.to_plan.code, amount_cents: @plan_change.to_plan.amount_cents },
          context: { kind: @plan_change.kind, strategy: "at_period_end" })
        @plan_change
      end
    end
  end
end
