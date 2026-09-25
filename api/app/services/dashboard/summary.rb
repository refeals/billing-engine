module Dashboard
  # The home screen's numbers: plain aggregate queries, cheap at demo size, so nothing is
  # cached and every figure is as of the current simulated time.
  class Summary
    RECENT_EVENTS = 10
    # Paying subscriptions. A trial hasn't paid yet, a paused one isn't billed and a canceled
    # one is gone; past_due still counts: that revenue is at risk, not lost yet.
    MRR_STATUSES = %w[active past_due].freeze

    def self.call
      new.call
    end

    def self.monthly_cents(interval, amount_cents)
      return amount_cents if interval == "month"

      # Rational#round rounds half away from zero: 59_000 / 12 = 4_916.67 → 4_917.
      Rational(amount_cents, 12).round
    end

    def call
      {
        simulated_now: BillingClock.now.iso8601,
        subscriptions_by_status: subscriptions_by_status,
        mrr_cents: mrr_cents,
        paying_subscriptions: Subscription.where(status: MRR_STATUSES).count,
        dunning: dunning,
        open_discrepancies: ReconciliationDiscrepancy.open.count,
        recent_events: BillingEvent.newest_first.limit(RECENT_EVENTS).map { |event| BillingEventSerializer.new(event).as_json }
      }
    end

    private

    # Every status is present, zero or not, so the screen never has to guess.
    def subscriptions_by_status
      counts = Subscription.group(:status).count
      SubscriptionStateMachine::STATES.index_with { |status| counts.fetch(status, 0) }
    end

    # Monthly recurring revenue from the plan each subscription is on now. A yearly price is
    # divided by 12 and rounded per subscription, so MRR always equals the sum of what each
    # subscription shows. Credit and refunds don't reduce it: MRR is what is contracted, not
    # what was collected.
    def mrr_cents
      Subscription.where(status: MRR_STATUSES).joins(:plan)
        .group("plans.interval", "plans.amount_cents").count
        .sum { |(interval, amount_cents), count| self.class.monthly_cents(interval, amount_cents) * count }
    end

    def dunning
      open_cases = DunningCase.open
      {
        open_cases: open_cases.count,
        # Everything the subscriptions in dunning still owe. Not just the invoice that opened
        # each case: a subscription keeps one case, and a second invoice can fail meanwhile
        # (an upgrade's proration, say).
        amount_at_risk_cents: Invoice.open.where(subscription_id: open_cases.select(:subscription_id)).sum(:amount_due_cents),
        by_step: open_cases.group(:last_step).count
      }
    end
  end
end
