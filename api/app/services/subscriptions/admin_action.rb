module Subscriptions
  # Shared rules for operator actions on an existing subscription.
  class AdminAction < ApplicationService
    def initialize(subscription, lock_version:, **options)
      @subscription = subscription
      @lock_version = lock_version
      @options = options
    end

    private

    attr_reader :subscription, :options

    # Uses the lock_version the operator's screen was loaded with, so saving fails with a
    # conflict (409) if anyone changed the subscription since, instead of silently acting
    # on a state the operator never saw.
    def with_guards(action)
      ActiveRecord::Base.transaction do
        # Stale screen first: if the subscription changed, the honest answer is "reload"
        # (409), even when the change also made this action unavailable.
        if @lock_version != subscription.lock_version
          raise ActiveRecord::StaleObjectError.new(subscription, action)
        end

        subscription.lock_version = @lock_version
        unless subscription.action_allowed?(action)
          raise DomainError.new("#{action.humanize} is not allowed while the subscription is #{subscription.status}",
            code: "action_not_allowed", details: { action: action, allowed_actions: subscription.allowed_actions })
        end

        yield
        subscription
      end
    end

    def now
      @now ||= BillingClock.now
    end
  end
end
