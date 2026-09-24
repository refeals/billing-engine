class ClockSerializer
  def initialize(now)
    @now = now
  end

  def as_json(*)
    { now: @now.iso8601 }
  end
end
