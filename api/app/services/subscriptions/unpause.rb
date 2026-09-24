module Subscriptions
  # Shared by the operator's Resume and the tick that ends a timed pause.
  class Unpause < ApplicationService
    def initialize(subscription, reason:)
      @subscription = subscription
      @reason = reason
    end

    def call
      Transition.call(@subscription, to: "active", reason: @reason, attributes: { paused_at: nil, resumes_at: nil })
    end
  end
end
