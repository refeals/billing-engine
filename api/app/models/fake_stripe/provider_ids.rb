module FakeStripe
  # Stripe-shaped identifiers (`cus_…`, `pm_…`). Generated locally for now; plan 06 moves
  # every call behind the payment gateway, where the provider hands them out.
  module ProviderIds
    def self.generate(prefix)
      "#{prefix}_#{SecureRandom.alphanumeric(14)}"
    end
  end
end
