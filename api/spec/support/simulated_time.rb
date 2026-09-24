# Most specs need a fixed "now" for both the real clock (travel_to) and the simulated one.
module SimulatedTime
  def freeze_clock_at(time)
    SimulationClock.find_or_create_by!(id: 1) { |clock| clock.current_time = time }.update!(current_time: time)
  end
end

RSpec.configure do |config|
  config.include SimulatedTime
  config.include ActiveSupport::Testing::TimeHelpers
  config.before { Current.actor = "admin" }
end
