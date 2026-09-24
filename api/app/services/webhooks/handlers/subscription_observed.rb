module Webhooks
  module Handlers
    # customer.subscription.* events echo the provider's view of a subscription. The engine
    # is the authority on subscription state (it decides trials, pauses and cancellations),
    # so these events are recorded, not applied. A disagreement shows up in the audit log
    # here and is resolved by reconciliation (plan 11).
    class SubscriptionObserved < Base
      def call
        subscription = Subscription.find_by(provider_subscription_id: object["id"])
        raise UnknownObject, "No subscription #{object['id']}" unless subscription
        return :skipped_stale if stale?(subscription)

        observe!(subscription)
        Audit.record(
          event_type: "provider.subscription_observed",
          subject: subscription,
          context: {
            event_type: webhook_event.event_type,
            provider_status: object["status"],
            engine_status: subscription.status,
            matches: object["status"] == subscription.status
          }
        )
        :processed
      end
    end
  end
end
