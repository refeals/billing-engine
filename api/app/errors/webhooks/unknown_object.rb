module Webhooks
  # The event is about a record we don't have (yet). Failing makes the provider retry later
  # instead of the event being silently dropped.
  class UnknownObject < StandardError; end
end
