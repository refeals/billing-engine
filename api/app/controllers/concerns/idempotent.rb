# Makes state-changing POSTs safe to retry. A client that sends an Idempotency-Key (the
# frontend does, once per dialog) gets the first response replayed for any retry of the
# same request, so a double click or a retry after a timeout never cancels twice.
module Idempotent
  extend ActiveSupport::Concern

  HEADER = "Idempotency-Key"

  included do
    around_action :with_idempotency_key, if: -> { request.post? && request.headers[HEADER].present? }
  end

  private

  def with_idempotency_key
    key = request.headers[HEADER]
    fingerprint = Digest::SHA256.hexdigest([ request.request_method, request.path, request.raw_post ].join("\n"))

    existing = IdempotencyKey.find_by(key: key)
    return replay_or_refuse(existing, fingerprint) if existing

    record = claim(key, fingerprint)
    return unless record

    stored = false
    begin
      # Errors handled by rescue_from (422, 404, 409) are rendered here so they are stored
      # and replayed like any other response.
      begin
        yield
      rescue StandardError => error
        raise unless rescue_with_handler(error)
      end

      # 5xx means "unknown outcome"; keeping it would stop a retry from ever running.
      if response.status < 500
        record.update!(response_status: response.status, response_body: response.body)
        stored = true
      end
    ensure
      record.destroy unless stored
    end
  end

  def claim(key, fingerprint)
    IdempotencyKey.create!(key: key, request_fingerprint: fingerprint)
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    render_error(:conflict, "idempotency_key_in_progress", "A request with this Idempotency-Key is still running")
    nil
  end

  def replay_or_refuse(existing, fingerprint)
    if existing.request_fingerprint != fingerprint
      render_error(:conflict, "idempotency_key_reused", "This Idempotency-Key was already used for a different request")
    elsif !existing.completed?
      render_error(:conflict, "idempotency_key_in_progress", "A request with this Idempotency-Key is still running")
    else
      response.headers["Idempotent-Replayed"] = "true"
      render status: existing.response_status, json: existing.response_body
    end
  end
end
