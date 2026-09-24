module Webhooks
  module NullSignatureVerifier
    def self.verify!(payload:, headers:)
      true
    end
  end
end
