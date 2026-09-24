module PlanPeriod
  # End of a billing period that starts at `from`. Month arithmetic clamps to the end of
  # shorter months (Jan 31 + 1 month = Feb 28/29).
  def self.advance(from, plan)
    plan.interval == "year" ? from + 1.year : from + 1.month
  end
end
