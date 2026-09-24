module Webhooks
  # Runs the handler for one inbox row, exactly once.
  class ProcessEvent < ApplicationService
    Result = Data.define(:status, :webhook_event)

    def initialize(webhook_event)
      @webhook_event = webhook_event
    end

    def call
      status = ActiveRecord::Base.transaction do
        # Re-read under a lock: another delivery of the same event may have finished since
        # this one claimed the row. Side effects and the terminal status commit together
        # below, so whoever gets here second sees the final status and stops.
        @webhook_event.lock!
        next register_duplicate if @webhook_event.terminal?

        outcome = Current.set(actor: "webhook", webhook_event: @webhook_event) { dispatch }
        @webhook_event.update!(processing_status: outcome, processed_at: BillingClock.now,
          attempts: @webhook_event.attempts + 1, last_error: nil)
        outcome
      end

      Result.new(status: status.to_sym, webhook_event: @webhook_event)
    rescue StandardError => error
      mark_failed(error)
      Result.new(status: :failed, webhook_event: @webhook_event)
    end

    private

    def dispatch
      handler = Handlers::Registry.for(@webhook_event.event_type)
      return "ignored_unhandled" unless handler

      outcome = handler.call(@webhook_event).to_s
      if outcome == "skipped_stale"
        Audit.record(event_type: "webhook.skipped_stale", subject: @webhook_event,
          context: { provider_created_at: @webhook_event.provider_created_at.iso8601 })
      end
      outcome
    end

    def register_duplicate
      WebhookEvent.update_counters(@webhook_event.id, duplicate_deliveries_count: 1)
      Current.set(actor: "webhook", webhook_event: @webhook_event) do
        Audit.record(event_type: "webhook.duplicate_received", subject: @webhook_event,
          context: { provider_event_id: @webhook_event.provider_event_id, status: @webhook_event.processing_status })
      end
      @webhook_event.reload
      "duplicate"
    end

    # Separate transaction: the handler's changes were rolled back, the failure record must
    # not be. A failed row is retried by the next delivery or a manual reprocess.
    def mark_failed(error)
      ActiveRecord::Base.transaction do
        @webhook_event.reload
        @webhook_event.update!(processing_status: "failed", attempts: @webhook_event.attempts + 1,
          last_error: "#{error.class}: #{error.message}".truncate(2000))
        Current.set(actor: "webhook", webhook_event: @webhook_event) do
          Audit.record(event_type: "webhook.failed", subject: @webhook_event,
            context: { error: error.class.name, message: error.message.truncate(500) })
        end
      end
    end
  end
end
