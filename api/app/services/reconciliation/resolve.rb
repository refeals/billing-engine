module Reconciliation
  # Carries out the operator's choice for a discrepancy. Corrections to the engine go
  # through the same paths as everything else: the webhook inbox (so every side effect of
  # the event runs) or the state machine (which can refuse). Nothing is patched directly.
  class Resolve < ApplicationService
    def initialize(discrepancy, strategy:, note: nil)
      @discrepancy = discrepancy
      @strategy = strategy.to_s
      @note = note.to_s.strip.presence
    end

    def call
      check_strategy!
      # Redelivery and reprocessing run the inbox, which manages its own transactions, so
      # they happen before (not inside) the bookkeeping below.
      perform

      ActiveRecord::Base.transaction do
        @discrepancy.update!(status: @strategy == "acknowledge" ? "acknowledged" : "resolved", resolution: @strategy,
          resolution_note: @note, resolved_at: BillingClock.now)
        Audit.record(event_type: "discrepancy.resolved", subject: @discrepancy,
          context: { kind: @discrepancy.kind, resolution: @strategy, note: @note }.compact)
        @discrepancy
      end
    end

    private

    def check_strategy!
      if (reason = @discrepancy.blocked_resolutions[@strategy])
        raise DomainError.new(reason, code: "correction_not_allowed")
      end
      unless @discrepancy.available_resolutions.include?(@strategy)
        raise DomainError.new("#{@strategy.humanize} isn't available for this discrepancy",
          code: "resolution_not_available", details: { available: @discrepancy.available_resolutions })
      end
      return unless @strategy == "acknowledge" && @note.nil?

      raise DomainError.new("Acknowledging a discrepancy needs a note explaining why", code: "note_required")
    end

    def perform
      case @strategy
      when "redeliver"
        FakeStripe::Dispatcher.redeliver(FakeStripe::MockedWebhookEvent.find_by!(event_id: @discrepancy.subject_key))
      when "reprocess"
        Webhooks::ProcessEvent.call(WebhookEvent.find_by!(provider_event_id: @discrepancy.subject_key))
      when "apply_expected"
        apply_expected_status
      when "resync_provider"
        # The engine is the authority on subscription state: tell the provider again.
        subscription = @discrepancy.subscription
        PaymentGateway.current.update_subscription(subscription.provider_subscription_id, snapshot: subscription.provider_snapshot)
      end
    end

    def apply_expected_status
      subscription = @discrepancy.subscription
      target = @discrepancy.expected_value
      attributes = target == "canceled" ? { canceled_at: BillingClock.now, cancellation_reason: SubscriptionStateMachine::RECONCILIATION_REASON } : {}

      Current.set(actor: "reconciliation") do
        Subscriptions::Transition.call(subscription, to: target, reason: SubscriptionStateMachine::RECONCILIATION_REASON,
          attributes: attributes, metadata: { discrepancy_id: @discrepancy.id })
      end
    end
  end
end
