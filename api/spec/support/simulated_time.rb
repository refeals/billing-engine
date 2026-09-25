# Most specs need a fixed "now" for both the real clock (travel_to) and the simulated one.
module SimulatedTime
  def freeze_clock_at(time)
    BillingClock.travel_to!(time)
  end
end

RSpec.configure do |config|
  config.include SimulatedTime
  config.include ActiveSupport::Testing::TimeHelpers
  config.before { Current.actor = "admin" }
end
