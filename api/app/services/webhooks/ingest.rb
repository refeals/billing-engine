module Webhooks
  # Entry point for every provider event (the HTTP endpoint and the fake provider's
  # dispatcher). It records the event in the inbox first and processes it second,
  # in two transactions: if the handler fails, the inbox row and its error must survive the
  # rollback of the handler's changes, or the failure would leave no trace.
  class Ingest < ApplicationService
    REQUIRED_FIELDS = %w[id type created].freeze

    def initialize(raw_body:, headers: {})
      @raw_body = raw_body
      @headers = headers
    end

    def call
      SignatureVerifier.current.verify!(payload: @raw_body, headers: @headers)
      ProcessEvent.call(claim(parse))
    end

    private

    # Every way a body can be unreadable must end here as InvalidPayload (400). Anything that
    # escapes as another error becomes a 500, and a 500 makes the provider resend the same
    # broken body forever.
    def parse
      event = JSON.parse(@raw_body)
      raise InvalidPayload, "Payload must be a JSON object" unless event.is_a?(Hash)

      object = event["data"].is_a?(Hash) ? event["data"]["object"] : nil
      raise InvalidPayload, "data.object must be a JSON object" unless object.is_a?(Hash)

      missing = REQUIRED_FIELDS.reject { |field| event[field].present? }
      missing << "data.object.id" if object["id"].blank?
      raise InvalidPayload, "Missing fields: #{missing.join(', ')}" if missing.any?

      event.merge("created" => unix_timestamp(event["created"]))
    rescue JSON::ParserError
      raise InvalidPayload, "Payload is not valid JSON"
    end

    def unix_timestamp(value)
      Integer(value)
    rescue ArgumentError, TypeError
      raise InvalidPayload, "created must be a Unix timestamp"
    end

    # INSERT … ON CONFLICT (provider_event_id) DO NOTHING: whatever number of deliveries
    # race here, exactly one row exists afterwards. Duplicates are recognized in ProcessEvent,
    # under a lock, so the check and the side effects can't interleave.
    def claim(event)
      WebhookEvent.insert(
        {
          provider_event_id: event["id"].to_s,
          event_type: event["type"].to_s,
          provider_object_id: event.dig("data", "object", "id").to_s,
          payload: event,
          provider_created_at: Time.zone.at(event["created"]),
          received_at: BillingClock.now,
          processing_status: "received"
        },
        unique_by: :provider_event_id
      )
      WebhookEvent.find_by!(provider_event_id: event["id"].to_s)
    end
  end
end
