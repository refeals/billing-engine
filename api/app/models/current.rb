# Request-scoped context. Who is acting is set once at the edge (controller, webhook
# ingestor, tick) instead of being threaded through every service call.
class Current < ActiveSupport::CurrentAttributes
  attribute :actor
end
