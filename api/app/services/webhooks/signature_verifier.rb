module Webhooks
  # Where a real integration checks the `Stripe-Signature` header against the endpoint
  # secret before trusting a payload. The fake provider doesn't sign anything, so unsigned
  # events are accepted only while the simulator is on. Anywhere else the endpoint fails
  # closed until real verification exists, rather than letting anyone who can reach the URL
  # inject events.
  module SignatureVerifier
    def self.current
      Rails.configuration.x.simulator_enabled ? NullSignatureVerifier : RejectingSignatureVerifier
    end
  end
end
