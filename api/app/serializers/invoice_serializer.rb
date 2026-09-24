class InvoiceSerializer
  def initialize(invoice, detail: false)
    @invoice = invoice
    @detail = detail
  end

  def as_json(*)
    invoice = @invoice
    summary = {
      id: invoice.id,
      number: invoice.number,
      provider_invoice_id: invoice.provider_invoice_id,
      status: invoice.status,
      billing_reason: invoice.billing_reason,
      subscription_id: invoice.subscription_id,
      customer: invoice.customer.slice(:id, :name, :email),
      period_start: invoice.period_start.iso8601,
      period_end: invoice.period_end.iso8601,
      subtotal_cents: invoice.subtotal_cents,
      credit_applied_cents: invoice.credit_applied_cents,
      total_cents: invoice.total_cents,
      amount_paid_cents: invoice.amount_paid_cents,
      amount_refunded_cents: invoice.amount_refunded_cents,
      amount_due_cents: invoice.amount_due_cents,
      currency: invoice.currency,
      issued_at: invoice.issued_at.iso8601,
      paid_at: invoice.paid_at&.iso8601,
      attempt_count: invoice.attempt_count,
      payable: invoice.open_for_payment?
    }
    return summary unless @detail

    summary.merge(
      line_items: invoice.line_items.map do |line|
        line.slice(:id, :kind, :description, :amount_cents).merge(
          period_start: line.period_start&.iso8601, period_end: line.period_end&.iso8601
        )
      end,
      payment_attempts: invoice.payment_attempts.includes(:payment_method).map { |attempt| PaymentAttemptSerializer.new(attempt).as_json }
    )
  end
end
