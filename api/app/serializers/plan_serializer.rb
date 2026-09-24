class PlanSerializer
  def initialize(plan)
    @plan = plan
  end

  def as_json(*)
    {
      id: @plan.id,
      code: @plan.code,
      name: @plan.name,
      amount_cents: @plan.amount_cents,
      currency: @plan.currency,
      interval: @plan.interval,
      trial_days: @plan.trial_days,
      active: !@plan.archived?,
      archived_at: @plan.archived_at&.iso8601
    }
  end
end
