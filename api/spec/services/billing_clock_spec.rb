require "rails_helper"

RSpec.describe BillingClock do
  include ActiveSupport::Testing::TimeHelpers

  let(:real_now) { Time.zone.parse("2026-10-01 12:00:00") }

  around { |example| travel_to(real_now) { example.run } }

  before { Current.actor = "admin" }

  describe ".now" do
    it "starts at real time the first time it is read" do
      expect { described_class.now }.to change(SimulationClock, :count).from(0).to(1)
      expect(described_class.now).to eq(real_now)
    end

    it "uses the existing row when another request created it first" do
      SimulationClock.create!(id: 1, current_time: real_now - 3.days)
      allow(SimulationClock).to receive(:find_by).and_return(nil)

      expect(described_class.now).to eq(real_now - 3.days)
      expect(SimulationClock.count).to eq(1)
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

    it "reads zero-padded strings as decimal, not octal" do
      expect(described_class.advance!(days: "010")[:ticks_run]).to eq(10)
      expect(described_class.advance!(days: "08")[:ticks_run]).to eq(8)
    end

    [ 0, 31, -1, 1.5, "abc", nil ].each do |invalid|
      it "rejects #{invalid.inspect} days" do
        expect { described_class.advance!(days: invalid) }
          .to raise_error(DomainError) { |error| expect(error.code).to eq("invalid_days") }
      end
    end

    it "records one audit event per simulated day" do
      described_class.advance!(days: 2)

      events = BillingEvent.of_type("clock.day_advanced").order(:id)
      expect(events.map(&:occurred_at)).to eq([ real_now + 1.day, real_now + 2.days ])
      expect(events.map(&:actor_type)).to all(eq("admin"))
      expect(events.first.data).to eq(
        "before" => { "now" => real_now.iso8601 }, "after" => { "now" => (real_now + 1.day).iso8601 }
      )
    end

    it "runs tick steps as the system, whoever moved the clock" do
      actors = []
      allow(Ticks::Run).to receive(:call) { actors << Current.actor and {} }

      described_class.advance!(days: 1)

      expect(actors).to eq([ "system_job" ])
      expect(Current.actor).to eq("admin")
    end

    it "rolls the day back when a tick step fails" do
      allow(Ticks::Run).to receive(:call).and_raise("step failed")

      expect { described_class.advance!(days: 1) }.to raise_error("step failed")
      expect(described_class.now).to eq(real_now)
      expect(BillingEvent.count).to eq(0)
    end
  end

  describe ".reset!" do
    it "moves the clock back to real time" do
      described_class.advance!(days: 5)

      expect(described_class.reset!).to eq(real_now)
      expect(described_class.now).to eq(real_now)
    end

    it "records the reset in the audit log" do
      described_class.advance!(days: 5)
      described_class.reset!

      event = BillingEvent.of_type("clock.reset").sole
      expect(event.data).to eq(
        "before" => { "now" => (real_now + 5.days).iso8601 }, "after" => { "now" => real_now.iso8601 }
      )
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
