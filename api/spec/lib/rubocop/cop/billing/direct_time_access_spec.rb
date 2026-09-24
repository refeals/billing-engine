require "rubocop"
require "rubocop/rspec/support"
require Rails.root.join("lib/rubocop/cop/billing/direct_time_access").to_s

RSpec.describe RuboCop::Cop::Billing::DirectTimeAccess, :config do
  include RuboCop::RSpec::ExpectOffense

  it "flags reads of the real clock" do
    expect_offense(<<~RUBY)
      Time.current
      ^^^^^^^^^^^^ Use `BillingClock.now` instead of `Time.current`; real time bypasses the simulated clock.
      Time.zone.now
      ^^^^^^^^^^^^^ Use `BillingClock.now` instead of `Time.zone.now`; real time bypasses the simulated clock.
      ::Date.today
      ^^^^^^^^^^^^ Use `BillingClock.now` instead of `::Date.today`; real time bypasses the simulated clock.
      DateTime.now
      ^^^^^^^^^^^^ Use `BillingClock.now` instead of `DateTime.now`; real time bypasses the simulated clock.
    RUBY
  end

  it "accepts the simulated clock and unrelated calls" do
    expect_no_offenses(<<~RUBY)
      BillingClock.now
      BillingClock.now.to_date
      Time.zone.parse("2026-01-01")
      Date.new(2026, 1, 1)
    RUBY
  end
end
