module Webhooks
  module RejectingSignatureVerifier
    def self.verify!(payload:, headers:)
      raise InvalidSignature, "Webhook signature verification is not configured; refusing unsigned events"
    end
  end
end
