module FakeStripe
  # Stripe-shaped identifiers (`cus_…`, `pm_…`, `evt_…`). Only the fake provider hands them
  # out; the engine stores them but never makes one up.
  module ProviderIds
    def self.generate(prefix)
      "#{prefix}_#{SecureRandom.alphanumeric(14)}"
    end
  end
end
