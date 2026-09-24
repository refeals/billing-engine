module Webhooks
  module Handlers
    # A handler turns one provider event into engine changes and returns :processed or
    # :skipped_stale. It runs inside ProcessEvent's transaction, with Current.actor set to
    # "webhook" and Current.webhook_event set to the inbox row.
    class Base
      def self.call(webhook_event)
        new(webhook_event).call
      end

      def initialize(webhook_event)
        @webhook_event = webhook_event
      end

      private

      attr_reader :webhook_event

      def object
        webhook_event.payload.dig("data", "object")
      end

      def provider_created_at
        webhook_event.provider_created_at
      end

      # Providers don't guarantee delivery order. Each record remembers the newest event
      # applied to it, and anything older is skipped. The check is per record: an old event
      # about invoice A is still valid after a newer one about invoice B. Equal timestamps
      # are processed, since many events share one simulated tick.
      def stale?(record)
        record.last_provider_event_at.present? && record.last_provider_event_at > provider_created_at
      end

      # update_columns on purpose: noting that an event was seen is not a business change, so
      # it must not bump lock_version and turn an operator's open screen into a 409.
      def observe!(record)
        record.update_columns(last_provider_event_at: provider_created_at)
      end
    end
  end
end
