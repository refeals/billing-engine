module FakeStripe
  # Delivers outbox events to the engine's webhook inbox, through the same service the HTTP
  # endpoint uses (just without the network).
  module Dispatcher
    FLUSHING_KEY = :fake_stripe_dispatcher_flushing
    # Handlers can emit new events while we deliver (a status change is pushed back to the
    # provider, which reports it again). Bounded so a bug can't loop forever.
    MAX_PASSES = 10

    class << self
      # Delivery waits until every open transaction has committed. A real provider can only
      # react to what our database has committed; delivering earlier would let a webhook see
      # (and act on) data that might still roll back.
      def schedule_flush
        ActiveRecord.after_all_transactions_commit { flush }
      end

      # Delivers every pending event, oldest first. An event whose delivery fails (the inbox
      # answered "failed") stays pending and is tried again by a later flush, which is how
      # the provider's retry schedule is simulated.
      def flush
        return if ActiveSupport::IsolatedExecutionState[FLUSHING_KEY]

        ActiveSupport::IsolatedExecutionState[FLUSHING_KEY] = true
        begin
          attempted = []
          MAX_PASSES.times do
            batch = MockedWebhookEvent.pending.where.not(id: attempted).order(:id).to_a
            break if batch.empty?

            batch.each do |event|
              attempted << event.id
              deliver(event)
            end
          end
        ensure
          ActiveSupport::IsolatedExecutionState[FLUSHING_KEY] = false
        end
      end

      # Sends a delivered or dropped event (once) again: a manual redelivery.
      def redeliver(event)
        deliver(event, copies: 1)
      end

      private

      def deliver(event, copies: event.copies)
        results = []
        copies.times do
          results << post(event)
          # A failed copy means "try again later"; sending the rest now would only fail too.
          break if results.last == "failed"
        end

        if results.last == "failed"
          # Back to pending whatever it was before (even a dropped event delivered by hand),
          # so the retry schedule picks it up.
          event.update!(delivery_status: "pending", delivery_attempts: event.delivery_attempts + 1,
            last_delivery_result: "failed")
        else
          event.update!(delivery_status: "delivered", delivery_count: event.delivery_count + results.size,
            delivery_attempts: event.delivery_attempts + 1, last_delivery_result: results.first,
            last_delivered_at: BillingClock.now)
        end
      end

      def post(event)
        Webhooks::Ingest.call(raw_body: event.payload.to_json).status.to_s
      rescue DomainError => error
        # The inbox refused the body (400). Retrying the same body can't succeed.
        "rejected: #{error.code}"
      rescue StandardError => error
        # Anything else (the database busy, a bug in the inbox) is what a network error is
        # to a real provider: the delivery failed and will be retried. It must not escape,
        # because flushes run right after someone else's transaction committed, and that
        # caller's work is already done.
        Rails.error.report(error, handled: true, context: { event_id: event.event_id })
        "failed"
      end
    end
  end
end
