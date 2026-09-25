# Request-scoped context. Who is acting is set once at the edge (controller, webhook
# ingestor, tick) instead of being threaded through every service call.
class Current < ActiveSupport::CurrentAttributes
  attribute :actor
  # The signed-in browser session, set by Authentication for API requests.
  attribute :session
  # The provider event being processed, if any, so every change it causes can point back
  # to it.
  attribute :webhook_event
  # Set while a Scenario Lab scenario runs: the provider tags its events with the run, and
  # can be told to lose the next event of a given type.
  attribute :scenario_run
  attribute :drop_event_types

  def user
    session&.user
  end
end
