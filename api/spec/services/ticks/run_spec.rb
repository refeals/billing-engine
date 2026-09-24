require "rails_helper"

RSpec.describe Ticks::Run do
  let(:at) { Time.zone.parse("2026-10-02 00:00:00") }

  it "returns an empty report when no steps are registered" do
    expect(described_class.call(at: at, steps: [])).to eq({})
  end

  it "runs every step in order and sums their counters" do
    calls = []
    first_step = ->(at:) { calls << [ :first, at ] && { renewals: 2 } }
    second_step = ->(at:) { calls << [ :second, at ] && { renewals: 1, trials_ended: 1 } }

    report = described_class.call(at: at, steps: [ first_step, second_step ])

    expect(calls).to eq([ [ :first, at ], [ :second, at ] ])
    expect(report).to eq(renewals: 3, trials_ended: 1)
  end
end
