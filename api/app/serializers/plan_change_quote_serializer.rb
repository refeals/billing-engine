class PlanChangeQuoteSerializer
  def initialize(quote)
    @quote = quote
  end

  def as_json(*)
    quote = @quote
    {
      kind: quote.kind,
      strategy: quote.strategy,
      allowed_strategies: PlanChanges::Quote::STRATEGIES_BY_KIND.fetch(quote.kind),
      from_plan: quote.from_plan.slice(:id, :code, :name, :amount_cents),
      to_plan: quote.to_plan.slice(:id, :code, :name, :amount_cents),
      proration_date: quote.proration_date&.iso8601,
      # Sent back when applying: it carries the proration date, signed, so the amounts can't
      # drift from this preview and the date can't be chosen by the client.
      quote_token: PlanChanges::QuoteToken.issue(quote),
      effective_at: quote.effective_at.iso8601,
      remaining_ratio: quote.ratio && format("%.4f", quote.ratio),
      lines: quote.prorated? ? quote.invoice_lines.map { |line| line.slice(:kind, :description, :amount_cents) } : [],
      credit_cents: quote.credit_cents,
      charge_cents: quote.charge_cents,
      net_cents: quote.net_cents,
      credit_applied_cents: quote.credit_applied_cents,
      amount_due_now_cents: quote.amount_due_now_cents,
      credit_to_balance_cents: quote.credit_to_balance_cents
    }
  end
end
