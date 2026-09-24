# The only write path for customer credit. Every movement is a ledger row; the balance on
# the customer is a cache updated in the same transaction, never written on its own.
module CreditLedger
  class << self
    # Both take a positive amount; the method decides the sign. A negative amount is a caller
    # bug, and flipping it silently would grant credit where a debit was meant.
    def credit!(customer, amount_cents:, reason:, **references)
      record!(customer, positive!(amount_cents), reason, references)
    end

    def debit!(customer, amount_cents:, reason:, **references)
      record!(customer, -positive!(amount_cents), reason, references)
    end

    private

    def positive!(amount_cents)
      raise ArgumentError, "amount_cents must be a positive Integer, got #{amount_cents.inspect}" unless amount_cents.is_a?(Integer) && amount_cents.positive?

      amount_cents
    end

    def record!(customer, amount_cents, reason, references)
      ActiveRecord::Base.transaction do
        # Serializes concurrent movements on the same customer, so two debits can't both
        # pass the balance check.
        customer.lock!
        balance_before = customer.credit_balance_cents
        balance_after = balance_before + amount_cents

        if balance_after.negative?
          raise DomainError.new("Not enough credit to cover this debit", code: "insufficient_credit",
            details: { balance_cents: balance_before, requested_cents: -amount_cents })
        end

        entry = customer.credit_ledger_entries.create!(amount_cents: amount_cents, balance_after_cents: balance_after,
          reason: reason, occurred_at: BillingClock.now, **references.slice(:invoice_id, :plan_change_id, :note))
        customer.update!(credit_balance_cents: balance_after)

        Audit.record(event_type: amount_cents.positive? ? "credit.granted" : "credit.applied", subject: entry,
          before: { credit_balance_cents: balance_before }, after: { credit_balance_cents: balance_after },
          context: { reason: reason, amount_cents: amount_cents, note: references[:note] }.compact)
        entry
      end
    end
  end
end
