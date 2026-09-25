module Webhooks
  # One payment attempt per provider charge, whichever event reports it first (charge.* or
  # invoice.*). The unique provider_charge_id is what keeps two different events about the
  # same charge from recording it twice.
  module PaymentAttemptRecorder
    # Returns the attempt, or nil when there was no charge (a $0 invoice).
    def self.record!(invoice:, charge_id:, status:, amount_cents:, at:, failure_code: nil, payment_method_id: nil, metadata: nil)
      return nil if charge_id.blank?

      existing = PaymentAttempt.find_by(provider_charge_id: charge_id)
      return existing if existing

      attempt = invoice.payment_attempts.create!(
        provider_charge_id: charge_id, status: status, failure_code: failure_code, amount_cents: amount_cents,
        payment_method: payment_method_id && PaymentMethod.find_by(provider_payment_method_id: payment_method_id),
        attempted_at: at, webhook_event_id: Current.webhook_event&.id,
        dunning_case_id: metadata&.dig("dunning_case_id"), dunning_step_id: metadata&.dig("dunning_step_id")
      )
      Audit.record(event_type: "payment.#{status}", subject: invoice,
        context: { provider_charge_id: charge_id, amount_cents: amount_cents, failure_code: failure_code }.compact)
      attempt
    end
  end
end
