class PlanChangeSerializer
  def initialize(plan_change)
    @plan_change = plan_change
  end

  def as_json(*)
    change = @plan_change
    {
      id: change.id,
      kind: change.kind,
      strategy: change.strategy,
      status: change.status,
      from_plan: change.from_plan.slice(:id, :code, :name, :amount_cents),
      to_plan: change.to_plan.slice(:id, :code, :name, :amount_cents),
      proration_date: change.proration_date&.iso8601,
      effective_at: change.effective_at.iso8601,
      credit_cents: change.credit_cents,
      charge_cents: change.charge_cents,
      net_cents: change.net_cents,
      invoice_id: change.invoice_id,
      created_at: change.created_at.iso8601
    }
  end
end
