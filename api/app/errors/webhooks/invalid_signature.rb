module Webhooks
  class InvalidSignature < DomainError
    def initialize(message = "Webhook signature could not be verified")
      super(message, code: "invalid_signature", http_status: :bad_request)
    end
  end
end
