module PlanChanges
  # Executes a plan change the operator previewed. The quote is recomputed here with the
  # preview's proration_date, so the amounts are the ones that were shown.
  class Apply < Subscriptions::AdminAction
    def call
      plan_change = nil
      with_guards("change_plan") do
        quote = Quote.new(subscription: subscription, to_plan: options.fetch(:to_plan),
          strategy: options[:strategy], proration_date: options[:proration_date])
        # A prorated change must reuse the preview's date; defaulting to "now" would charge an
        # amount the operator never saw.
        if quote.prorated? && options[:proration_date].blank?
          raise DomainError.new("The preview's quote_token is required for a prorated change", code: "quote_token_required")
        end
        plan_change = quote.strategy == "at_period_end" ? schedule(quote) : apply_now(quote)
      end
      plan_change
    end

    private

    def apply_now(quote)
      subscription.update!(plan: quote.to_plan)
      plan_change = PlanChange.create!(
        subscription: subscription, from_plan: quote.from_plan, to_plan: quote.to_plan, kind: quote.kind,
        strategy: "immediate", status: "applied", proration_date: quote.proration_date, effective_at: quote.effective_at,
        credit_cents: quote.credit_cents, charge_cents: quote.charge_cents, net_cents: quote.net_cents
      )

      if quote.kind == "upgrade"
        # Billed for the rest of the current period; the billing anchor doesn't move. If the
        # payment fails the plan stays changed and the subscription goes past_due, as with
        # any unpaid invoice (Stripe's default too).
        invoice = Invoices::Issue.call(subscription: subscription, billing_reason: "subscription_update",
          period_start: quote.proration_date, period_end: quote.period_end, lines: quote.invoice_lines)
        plan_change.update!(invoice: invoice)
      elsif quote.credit_to_balance_cents.positive?
        # The unused difference becomes credit, spent by the next invoices.
        CreditLedger.credit!(subscription.customer, amount_cents: quote.credit_to_balance_cents,
          reason: "downgrade_proration", plan_change_id: plan_change.id,
          note: "Downgrade from #{quote.from_plan.name} to #{quote.to_plan.name}")
      end

      Audit.record(event_type: "plan.changed", subject: plan_change,
        before: { plan: quote.from_plan.code, amount_cents: quote.from_plan.amount_cents },
        after: { plan: quote.to_plan.code, amount_cents: quote.to_plan.amount_cents },
        context: { kind: quote.kind, strategy: "immediate", proration_date: quote.proration_date&.iso8601,
                   credit_cents: quote.credit_cents, charge_cents: quote.charge_cents, net_cents: quote.net_cents }.compact)
      plan_change
    end

    def schedule(quote)
      subscription.plan_changes.scheduled.each { |previous| CancelScheduled.call(previous, reason: "replaced") }

      plan_change = PlanChange.create!(
        subscription: subscription, from_plan: quote.from_plan, to_plan: quote.to_plan, kind: quote.kind,
        strategy: "at_period_end", status: "scheduled", effective_at: quote.effective_at
      )
      # Bump the subscription's version: its state (what renews next) changed, so a screen
      # opened before this must not act on the old picture.
      subscription.touch
      Audit.record(event_type: "plan.change_scheduled", subject: plan_change,
        before: { plan: quote.from_plan.code }, after: { plan: quote.to_plan.code },
        context: { kind: quote.kind, effective_at: quote.effective_at.iso8601 })
      plan_change
    end
  end
end
