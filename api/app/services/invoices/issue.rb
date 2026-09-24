module Invoices
  # Builds, finalizes and sends an invoice for one billing period, in the caller's
  # transaction: lines, credit, number and provider id either all exist or none do. The
  # invoice is born `open`; it becomes `paid` only when the provider's webhook says so.
  class Issue < ApplicationService
    def initialize(subscription:, billing_reason:, period_start:, period_end:)
      @subscription = subscription
      @billing_reason = billing_reason
      @period_start = period_start
      @period_end = period_end
    end

    def call
      ActiveRecord::Base.transaction do
        invoice = build_invoice
        invoice.provider_invoice_id = PaymentGateway.current.create_invoice(snapshot: provider_snapshot(invoice))
        invoice.save!

        invoice.line_items.create!(kind: "subscription", plan: plan, amount_cents: plan.amount_cents,
          description: "#{plan.name} (#{@period_start.to_date} – #{@period_end.to_date})",
          period_start: @period_start, period_end: @period_end)
        apply_credit(invoice) if invoice.credit_applied_cents.positive?

        Audit.record(event_type: "invoice.issued", subject: invoice,
          after: invoice.slice(:number, :billing_reason, :subtotal_cents, :credit_applied_cents, :total_cents, :amount_due_cents),
          context: { period_start: @period_start.iso8601, period_end: @period_end.iso8601 })

        RequestPayment.call(invoice)
        invoice
      end
    end

    private

    def plan
      @subscription.plan
    end

    def customer
      @subscription.customer
    end

    def build_invoice
      now = BillingClock.now
      subtotal = plan.amount_cents
      # Credit from earlier downgrades or refunds is spent before the card is charged.
      credit = [ customer.reload.credit_balance_cents, subtotal ].min
      total = subtotal - credit

      Invoice.new(
        subscription: @subscription, customer: customer, number: InvoiceNumber.next!(now.year),
        status: "open", billing_reason: @billing_reason, period_start: @period_start, period_end: @period_end,
        subtotal_cents: subtotal, credit_applied_cents: credit, total_cents: total, amount_due_cents: total,
        issued_at: now
      )
    end

    def apply_credit(invoice)
      CreditLedger.debit!(customer, amount_cents: invoice.credit_applied_cents, reason: "applied_to_invoice",
        invoice_id: invoice.id, note: "Applied to #{invoice.number}")
      invoice.line_items.create!(kind: "credit_applied", amount_cents: -invoice.credit_applied_cents,
        description: "Credit balance applied")
    end

    def provider_snapshot(invoice)
      {
        customer: customer.provider_customer_id, subscription: @subscription.provider_subscription_id,
        number: invoice.number, total_cents: invoice.total_cents, amount_due_cents: invoice.amount_due_cents
      }
    end
  end
end
