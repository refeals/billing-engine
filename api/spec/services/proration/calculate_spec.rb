require "rails_helper"

RSpec.describe Proration::Calculate do
  # October 2026 has 31 days: a period whose ratios are rarely round numbers.
  let(:period_start) { Time.utc(2026, 10, 1) }
  let(:period_end) { Time.utc(2026, 11, 1) }

  def calculate(old_cents, new_cents, date)
    described_class.call(old_amount_cents: old_cents, new_amount_cents: new_cents,
      period_start: period_start, period_end: period_end, proration_date: date)
  end

  [
    # description,                  old,  new,  proration date,                       credit, charge, net
    [ "at the very start",           4900, 9900, Time.utc(2026, 10, 1),                 -4900,  9900,   5000 ],
    [ "at the very end",             4900, 9900, Time.utc(2026, 11, 1),                     0,     0,      0 ],
    [ "at exactly half the period",  4900, 9900, Time.utc(2026, 10, 16, 12),            -2450,  4950,   2500 ],
    [ "on day 11 of 31 (21 left)",   4900, 9900, Time.utc(2026, 10, 11),                -3319,  6706,   3387 ],
    [ "rounding halves up",           999, 1999, Time.utc(2026, 10, 16, 12),             -500,  1000,    500 ],
    [ "a downgrade",                 9900, 4900, Time.utc(2026, 10, 11),                -6706,  3319,  -3387 ]
  ].each do |description, old_cents, new_cents, date, credit, charge, net|
    it "prorates #{description}" do
      result = calculate(old_cents, new_cents, date)

      expect([ result.credit_cents, result.charge_cents, result.net_cents ]).to eq([ credit, charge, net ])
    end
  end

  it "keeps the ratio exact (no float error)" do
    expect(calculate(4900, 9900, Time.utc(2026, 10, 11)).ratio).to eq(Rational(21, 31))
  end

  it "always makes the lines add up to the net, whatever the amounts and dates" do
    random = Random.new(42)
    200.times do
      date = period_start + random.rand(0..(31 * 86_400))
      result = calculate(random.rand(1..50_000), random.rand(1..50_000), date)

      expect(result.credit_cents + result.charge_cents).to eq(result.net_cents)
    end
  end

  it "refuses a date outside the period" do
    expect { calculate(4900, 9900, Time.utc(2026, 11, 2)) }.to raise_error(ArgumentError)
  end
end
