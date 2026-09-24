module Subscriptions
  # The single write path for subscription status. It checks the move against the state
  # machine, then changes the status, writes the audit event and the transition row in one
  # transaction, so a status can never change without its history.
  class Transition < ApplicationService
    def initialize(subscription, to:, reason:, attributes: {}, metadata: {})
      @subscription = subscription
      @to = to
      @reason = reason
      @attributes = attributes
      @metadata = metadata
    end

    def call
      from = @subscription.new_record? ? nil : @subscription.status_in_database
      SubscriptionStateMachine.assert!(from, @to, @reason)

      ActiveRecord::Base.transaction do
        @subscription.assign_attributes(@attributes.merge(status: @to))
        changes = @subscription.changes_to_save.except("id", "lock_version", "updated_at", "created_at")
        @subscription.applying_transition { @subscription.save! }

        event = Audit.record(
          event_type: "subscription.transitioned",
          subject: @subscription,
          before: changes.transform_values { |(before, _)| serialize(before) },
          after: changes.transform_values { |(_, after)| serialize(after) },
          context: { reason: @reason, **@metadata }
        )
        @subscription.state_transitions.create!(
          from_status: from, to_status: @to, reason: @reason, actor_type: event.actor_type,
          webhook_event_id: event.webhook_event_id, billing_event: event, metadata: @metadata,
          occurred_at: event.occurred_at
        )
        # A canceled subscription never renews, so a change waiting for renewal would stay
        # "scheduled" forever. Every cancellation path comes through here.
        if @to == "canceled"
          @subscription.plan_changes.scheduled.each do |plan_change|
            PlanChanges::CancelScheduled.call(plan_change, reason: "subscription_canceled")
          end
        end
        @subscription
      end
    end

    private

    def serialize(value)
      value.respond_to?(:iso8601) ? value.iso8601 : value
    end
  end
end
