module Ticks
  # The fake provider's retry schedule: once per simulated day, events whose delivery failed
  # (the inbox answered 500) are sent again, after that day's changes commit.
  class RetryProviderDeliveries
    def self.call(at:)
      # Only deliveries that already failed. Events emitted earlier in this same tick are
      # pending too, but just because their transaction hasn't committed yet; counting them
      # would report retries that aren't happening.
      awaiting_retry = FakeStripe::MockedWebhookEvent.pending.where("delivery_attempts > 0").count
      FakeStripe::Dispatcher.schedule_flush if awaiting_retry.positive?

      { provider_deliveries_retried: awaiting_retry }
    end
  end
end
