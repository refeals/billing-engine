class ScenarioRunSerializer
  def initialize(run)
    @run = run
  end

  def as_json(*)
    @run.slice(:id, :scenario_key, :status, :error, :log, :customer_id, :subscription_id)
      .merge(title: title, started_at: @run.started_at.iso8601, finished_at: @run.finished_at&.iso8601)
  end

  private

  # A run outlives code changes: a scenario renamed or removed since must not break the list.
  def title
    Scenarios::Catalog.all.find { |scenario| scenario.key == @run.scenario_key }&.title ||
      @run.scenario_key.humanize
  end
end
