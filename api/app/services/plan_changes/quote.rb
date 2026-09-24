module PlanChanges
  # Everything a plan change would do, computed without doing it. The preview endpoint shows
  # it and Apply executes it, so both always agree: what the operator saw is what is charged.
  class Quote
    STRATEGIES_BY_KIND = {
      "trial_swap" => %w[immediate],
      # Paying less later for something better now isn't offered: upgrades bill right away.
      "upgrade" => %w[immediate],
      "downgrade" => %w[immediate at_period_end],
      "lateral" => %w[immediate at_period_end]
    }.freeze

    attr_reader :subscription, :from_plan, :to_plan, :kind, :strategy, :proration_date, :effective_at,
      :credit_cents, :charge_cents, :net_cents, :credit_applied_cents, :amount_due_now_cents,
      :credit_to_balance_cents, :ratio

    def initialize(subscription:, to_plan:, strategy:, proration_date: nil)
      @subscription = subscription
      @from_plan = subscription.plan
      @to_plan = to_plan
      @now = BillingClock.now
      validate_target!
      @kind = determine_kind
      @strategy = validate_strategy!(strategy.presence || "immediate")
      @proration_date = prorated? ? validate_proration_date!(proration_date || @now) : nil
      compute
    end

    def prorated?
      strategy == "immediate" && %w[upgrade downgrade lateral].include?(kind)
    end

    # The lines a proration invoice carries (only upgrades produce one).
    def invoice_lines
      [
        { kind: "proration_credit", plan: from_plan, amount_cents: credit_cents,
          description: "Unused time on #{from_plan.name}", period_start: proration_date, period_end: period_end },
        { kind: "proration_charge", plan: to_plan, amount_cents: charge_cents,
          description: "Remaining time on #{to_plan.name}", period_start: proration_date, period_end: period_end }
      ]
    end

    def period_start
      subscription.current_period_start
    end

    def period_end
      subscription.current_period_end
    end

    private

    def validate_target!
      unless subscription.action_allowed?("change_plan")
        refuse!("A #{subscription.status} subscription can't change plans#{' while a cancellation is scheduled' if subscription.cancel_at_period_end?}",
          "action_not_allowed")
      end
      refuse!("The subscription is already on #{to_plan.name}", "same_plan") if to_plan.id == from_plan.id
      refuse!("#{to_plan.name} is archived", "plan_archived") if to_plan.archived?
      return if to_plan.interval == from_plan.interval

      refuse!("Changing between monthly and yearly billing isn't supported", "interval_change_not_supported")
    end

    def determine_kind
      return "trial_swap" if subscription.status == "trialing"

      case to_plan.amount_cents <=> from_plan.amount_cents
      when 1 then "upgrade"
      when -1 then "downgrade"
      else "lateral"
      end
    end

    def validate_strategy!(strategy)
      allowed = STRATEGIES_BY_KIND.fetch(kind)
      return strategy if allowed.include?(strategy)

      refuse!("A #{kind.humanize(capitalize: false)} can only be applied #{allowed.map(&:humanize).join(' or ').downcase}",
        "strategy_not_allowed", allowed: allowed)
    end

    # The date is echoed back by the client from the preview. It has to still make sense: the
    # period may have been renewed since (the clock moved on), in which case recomputing would
    # charge an amount nobody saw.
    def validate_proration_date!(value)
      date = value.is_a?(String) ? Time.iso8601(value) : value
      return date if date >= period_start && date < period_end && date <= @now

      raise DomainError.new("This preview is no longer valid: the billing period changed. Preview again.",
        code: "stale_preview", http_status: :conflict,
        details: { proration_date: date.iso8601, period_start: period_start.iso8601, period_end: period_end.iso8601 })
    rescue ArgumentError
      refuse!("proration_date must be an ISO 8601 time", "invalid_proration_date")
    end

    def compute
      @effective_at = strategy == "at_period_end" ? period_end : (proration_date || @now)
      @credit_cents = @charge_cents = @net_cents = @credit_applied_cents = @amount_due_now_cents = @credit_to_balance_cents = 0
      return unless prorated?

      result = Proration::Calculate.call(old_amount_cents: from_plan.amount_cents, new_amount_cents: to_plan.amount_cents,
        period_start: period_start, period_end: period_end, proration_date: proration_date)
      @ratio = result.ratio
      @credit_cents = result.credit_cents
      @charge_cents = result.charge_cents
      @net_cents = result.net_cents

      if kind == "upgrade"
        # The proration invoice spends existing credit first, like any other invoice.
        @credit_applied_cents = [ subscription.customer.credit_balance_cents, net_cents ].min
        @amount_due_now_cents = net_cents - credit_applied_cents
      elsif net_cents.negative?
        @credit_to_balance_cents = -net_cents
      end
    end

    def refuse!(message, code, **details)
      raise DomainError.new(message, code: code, details: details)
    end
  end
end
