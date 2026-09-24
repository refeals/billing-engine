module Webhooks
  # The request is not a provider event we can read. 400: retrying the same body can't help.
  class InvalidPayload < DomainError
    def initialize(message)
      super(message, code: "invalid_payload", http_status: :bad_request)
    end
  end
end
