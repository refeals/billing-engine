require "rails_helper"

RSpec.describe Audit do
  include ActiveSupport::Testing::TimeHelpers

  let(:simulated_now) { Time.zone.parse("2026-10-15 09:30:00") }
  let(:subject_record) { SimulationClock.create!(id: 1, current_time: simulated_now) }

  around { |example| travel_to(simulated_now - 3.days) { example.run } }

  before { Current.actor = "admin" }

  def record(**overrides)
    ActiveRecord::Base.transaction do
      described_class.record(event_type: "clock.day_advanced", subject: subject_record, **overrides)
    end
  end

  it "stores the event with simulated time and the current actor" do
    event = record(before: { now: "a" }, after: { now: "b" }, context: { reason: "demo" })

    expect(event).to have_attributes(
      event_type: "clock.day_advanced",
      actor_type: "admin",
      subject: subject_record,
      occurred_at: simulated_now,
      data: { "before" => { "now" => "a" }, "after" => { "now" => "b" }, "context" => { "reason" => "demo" } }
    )
  end

  it "omits empty data sections" do
    expect(record.data).to eq({})
  end

  it "lets the caller override the actor" do
    expect(record(actor: "reconciliation").actor_type).to eq("reconciliation")
  end

  it "fills subscription and customer from the subject's audit references" do
    allow(subject_record).to receive(:audit_references).and_return(subscription_id: 7, customer_id: 3)

    expect(record).to have_attributes(subscription_id: 7, customer_id: 3)
  end

  it "raises outside a transaction instead of writing half a story" do
    expect { described_class.record(event_type: "clock.reset", subject: subject_record) }
      .to raise_error(Audit::OutsideTransactionError)
  end

  it "raises when no actor is known" do
    Current.actor = nil

    expect { record }.to raise_error(ArgumentError, /actor/)
  end

  it "rolls back together with the caller's transaction" do
    ActiveRecord::Base.transaction do
      described_class.record(event_type: "clock.reset", subject: subject_record)
      raise ActiveRecord::Rollback
    end

    expect(BillingEvent.count).to eq(0)
  end
end
