# Base class for business-rule violations. Carrying a stable `code` lets the frontend
# react to a specific failure without parsing human-readable messages.
class DomainError < StandardError
  attr_reader :code, :details, :http_status

  def initialize(message = nil, code: "domain_error", details: {}, http_status: :unprocessable_content)
    super(message)
    @code = code
    @details = details
    @http_status = http_status
  end
end
