# Request-scoped context. Who is acting is set once at the edge (controller, webhook
# ingestor, tick) instead of being threaded through every service call.
class Current < ActiveSupport::CurrentAttributes
  attribute :actor
  # The provider event being processed, if any, so every change it causes can point back
  # to it.
  attribute :webhook_event
end
