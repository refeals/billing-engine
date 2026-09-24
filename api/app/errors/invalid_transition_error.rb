class InvalidTransitionError < DomainError
  def initialize(message = nil, details: {})
    super(message, code: "invalid_transition", details: details)
  end
end
