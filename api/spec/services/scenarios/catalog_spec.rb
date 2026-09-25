require "rails_helper"

# The Scenario Lab's scenarios are also the test suite's: if one stops passing here, the
# demo is broken.
RSpec.describe Scenarios::Catalog do
  before { freeze_clock_at(Time.utc(2026, 3, 16, 9)) }

  described_class.all.each do |scenario|
    it "passes #{scenario.key}" do
      run = scenario.call

      expect(run.error).to be_nil
      expect(run).to have_attributes(status: "passed", scenario_key: scenario.key)
      expect(run.log).to include(include("step" => start_with("✓")))
    end
  end

  it "reports a failed expectation as a failed run instead of raising" do
    failing = Class.new(Scenarios::Base) do
      scenario key: "failing", title: "Failing", description: "Checks something false."

      def steps
        customer
        expect_that("two plus two is five") { 2 + 2 == 5 }
      end
    end

    run = failing.call

    expect(run).to have_attributes(status: "failed", error: "Expectation failed: two plus two is five")
    expect(run.log.first["step"]).to eq("Customer created")
  end

  it "tags the provider events a run produced and can lose the next event of a type" do
    run = Scenarios::LostWebhook.call

    events = FakeStripe::MockedWebhookEvent.where(scenario_run_id: run.id)
    expect(events.where(event_type: "invoice.paid").pluck(:delivery_status)).to eq(%w[dropped])
    expect(events.where(event_type: "charge.succeeded").pluck(:delivery_status)).to eq(%w[delivered])
  end
end
