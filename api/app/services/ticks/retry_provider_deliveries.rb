module Ticks
  # The fake provider's retry schedule: once per simulated day, events whose delivery failed
  # (the inbox answered 500) are sent again, after that day's changes commit.
  class RetryProviderDeliveries
    def self.call(at:)
      pending = FakeStripe::MockedWebhookEvent.pending.count
      FakeStripe::Dispatcher.schedule_flush if pending.positive?

      { provider_deliveries_pending: pending }
    end
  end
end
