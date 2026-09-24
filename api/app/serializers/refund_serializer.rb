class RefundSerializer
  def initialize(refund)
    @refund = refund
  end

  def as_json(*)
    @refund.slice(:id, :provider_refund_id, :amount_cents, :destination, :reason, :status, :failure_reason)
      .merge(requested_at: @refund.requested_at.iso8601, completed_at: @refund.completed_at&.iso8601)
  end
end
