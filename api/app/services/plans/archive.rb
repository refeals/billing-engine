module Plans
  # Archiving hides a plan from new subscriptions and plan changes; current subscribers
  # keep it. Plans are never deleted, because invoices and history point at them.
  class Archive < ApplicationService
    def initialize(plan)
      @plan = plan
    end

    def call
      ActiveRecord::Base.transaction do
        @plan.lock!
        raise DomainError.new("Plan #{@plan.code} is already archived", code: "plan_already_archived") if @plan.archived?

        @plan.update!(archived_at: BillingClock.now)
        Audit.record(event_type: "plan.archived", subject: @plan, before: { archived_at: nil },
          after: { archived_at: @plan.archived_at.iso8601 })
        @plan
      end
    end
  end
end
