module Subscriptions
  class Resume < AdminAction
    def call
      with_guards("resume") do
        Subscriptions::Unpause.call(subscription, reason: "customer_requested")
      end
    end
  end
end
