module Refunds
  class Create < ApplicationService
    def initialize(invoice, amount_cents:, destination:, reason:)
      @invoice = invoice
      @amount_cents = amount_cents
      @destination = destination.presence || "original_method"
      @reason = reason.presence || "requested_by_customer"
    end

    def call
      ActiveRecord::Base.transaction do
        # Serializes refunds of the same invoice, so two requests can't both see the same
        # refundable amount (SQLite's IMMEDIATE transactions do it already; the lock does it
        # on databases with row locks).
        @invoice.lock!
        check_refundable!

        refund = @destination == "credit_balance" ? refund_to_balance : refund_to_card
        Audit.record(event_type: "refund.requested", subject: refund,
          after: refund.slice(:amount_cents, :destination, :reason, :status),
          context: { invoice: @invoice.number, refundable_before_cents: @refundable_cents })
        refund
      end
    end

    private

    def check_refundable!
      unless @invoice.paid?
        raise DomainError.new("Only paid invoices can be refunded (#{@invoice.number} is #{@invoice.status})",
          code: "invoice_not_refundable")
      end
      unless @amount_cents.is_a?(Integer) && @amount_cents.positive?
        raise DomainError.new("amount_cents must be a positive whole number of cents", code: "invalid_amount")
      end
      # Checked before anything reaches the provider.
      unless Refund::DESTINATIONS.include?(@destination) && Refund::REASONS.include?(@reason)
        raise DomainError.new("destination must be one of #{Refund::DESTINATIONS.join(', ')} and reason one of #{Refund::REASONS.join(', ')}",
          code: "invalid_refund", details: { destination: @destination, reason: @reason })
      end

      @refundable_cents = @invoice.refundable_cents
      return if @amount_cents <= @refundable_cents

      raise DomainError.new("Only #{@refundable_cents} cents can still be refunded on #{@invoice.number}",
        code: "refund_exceeds_refundable", details: { refundable_cents: @refundable_cents, requested_cents: @amount_cents })
    end

    # The money goes back to the card through the provider. The refund stays pending until
    # the provider's refund.updated event says whether it went through.
    def refund_to_card
      charge = @invoice.payment_attempts.succeeded.last
      unless charge
        raise DomainError.new("#{@invoice.number} has no card charge to refund; refund to the credit balance instead",
          code: "no_charge_to_refund")
      end

      card = charge.payment_method
      provider_refund_id = PaymentGateway.current.refund(
        charge: charge.provider_charge_id, amount_cents: @amount_cents, reason: @reason,
        payment_method: card && { id: card.provider_payment_method_id, token: card.test_card_token }
      )
      @invoice.refunds.create!(payment_attempt: charge, provider_refund_id: provider_refund_id, amount_cents: @amount_cents,
        destination: "original_method", reason: @reason, status: "pending", requested_at: BillingClock.now)
    end

    # No money leaves: the amount becomes credit that the next invoices spend. Done at once.
    def refund_to_balance
      now = BillingClock.now
      refund = @invoice.refunds.create!(amount_cents: @amount_cents, destination: "credit_balance", reason: @reason,
        status: "succeeded", requested_at: now, completed_at: now)
      @invoice.update!(amount_refunded_cents: @invoice.amount_refunded_cents + @amount_cents)
      CreditLedger.credit!(@invoice.customer, amount_cents: @amount_cents, reason: "refund_to_balance",
        invoice_id: @invoice.id, note: "Refund of #{@invoice.number}")
      Audit.record(event_type: "refund.succeeded", subject: refund,
        after: { status: "succeeded", invoice_amount_refunded_cents: @invoice.amount_refunded_cents })
      refund
    end
  end
end
