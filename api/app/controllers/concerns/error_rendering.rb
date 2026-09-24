# Every error leaves the API in the same shape, so the frontend has a single parser.
module ErrorRendering
  extend ActiveSupport::Concern

  included do
    rescue_from DomainError do |error|
      render_error(error.http_status, error.code, error.message, error.details)
    end

    rescue_from ActiveRecord::StaleObjectError do
      render_error(:conflict, "stale_object", "This record was changed by someone else. Reload and try again.")
    end

    rescue_from ActiveRecord::RecordNotFound do |error|
      render_error(:not_found, "not_found", error.message)
    end

    rescue_from ActiveRecord::RecordInvalid do |error|
      render_error(:unprocessable_content, "validation_failed", error.message, error.record.errors.to_hash)
    end

    rescue_from ActionController::ParameterMissing do |error|
      render_error(:bad_request, "bad_request", error.message)
    end
  end

  private

  def render_error(status, code, message, details = {})
    render status: status, json: { error: { code: code, message: message, details: details } }
  end
end
