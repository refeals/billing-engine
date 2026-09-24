module Plans
  class Create < ApplicationService
    def initialize(attributes)
      @attributes = attributes
    end

    def call
      ActiveRecord::Base.transaction do
        plan = Plan.create!(@attributes)
        Audit.record(event_type: "plan.created", subject: plan, after: snapshot(plan))
        plan
      end
    end

    private

    def snapshot(plan)
      plan.slice(:code, :name, :amount_cents, :currency, :interval, :trial_days)
    end
  end
end
