class PaymentAttemptSerializer
  def initialize(attempt)
    @attempt = attempt
  end

  def as_json(*)
    card = @attempt.payment_method
    {
      id: @attempt.id,
      provider_charge_id: @attempt.provider_charge_id,
      status: @attempt.status,
      failure_code: @attempt.failure_code,
      amount_cents: @attempt.amount_cents,
      attempted_at: @attempt.attempted_at.iso8601,
      webhook_event_id: @attempt.webhook_event_id,
      card: card && { brand: card.brand, last4: card.last4 }
    }
  end
end
