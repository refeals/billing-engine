require "rails_helper"

RSpec.describe BillingClock do
  include ActiveSupport::Testing::TimeHelpers

  let(:real_now) { Time.zone.parse("2026-10-01 12:00:00") }

  around { |example| travel_to(real_now) { example.run } }

  describe ".now" do
    it "starts at real time the first time it is read" do
      expect { described_class.now }.to change(SimulationClock, :count).from(0).to(1)
      expect(described_class.now).to eq(real_now)
    end
  end

  describe ".advance!" do
    it "moves the clock forward by whole days" do
      result = described_class.advance!(days: 3)

      expect(result[:now]).to eq(real_now + 3.days)
      expect(described_class.now).to eq(real_now + 3.days)
    end

    it "runs one tick per simulated day, in order" do
      ticked_at = []
      allow(Ticks::Run).to receive(:call) do |at:|
        ticked_at << at
        { renewals: 1 }
      end

      result = described_class.advance!(days: 3)

      expect(ticked_at).to eq([ real_now + 1.day, real_now + 2.days, real_now + 3.days ])
      expect(result[:ticks_run]).to eq(3)
      expect(result[:tick_report]).to eq(renewals: 3)
    end

    it "accepts days as a numeric string, as it arrives from params" do
      expect(described_class.advance!(days: "2")[:ticks_run]).to eq(2)
    end

    [ 0, 31, -1, 1.5, "abc", nil ].each do |invalid|
      it "rejects #{invalid.inspect} days" do
        expect { described_class.advance!(days: invalid) }
          .to raise_error(DomainError) { |error| expect(error.code).to eq("invalid_days") }
      end
    end

    it "rolls the day back when a tick step fails" do
      allow(Ticks::Run).to receive(:call).and_raise("step failed")

      expect { described_class.advance!(days: 1) }.to raise_error("step failed")
      expect(described_class.now).to eq(real_now)
    end
  end

  describe ".reset!" do
    it "moves the clock back to real time" do
      described_class.advance!(days: 5)

      expect(described_class.reset!).to eq(real_now)
      expect(described_class.now).to eq(real_now)
    end
  end

  describe "moving backwards" do
    it "is refused outside reset" do
      clock = SimulationClock.create!(id: 1, current_time: real_now)

      expect { clock.update!(current_time: real_now - 1.day) }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "cannot create a second clock row" do
      SimulationClock.create!(id: 1, current_time: real_now)

      expect { SimulationClock.create!(id: 2, current_time: real_now) }.to raise_error(ActiveRecord::StatementInvalid)
    end
  end
end
