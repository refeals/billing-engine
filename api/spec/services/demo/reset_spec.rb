require "rails_helper"

RSpec.describe Demo::Reset do
  before { freeze_clock_at(Time.utc(2026, 10, 1)) }

  it "wipes everything, including append-only history, and restores the append-only guarantees" do
    subscribe(customer_with_card)
    expect(BillingEvent.count).to be_positive

    described_class.call(reseed: false)

    expect([ BillingEvent, Subscription, FakeStripe::MockedWebhookEvent, Customer ].map(&:count)).to all(eq(0))
    event = BillingEvent.create!(event_type: "clock.reset", actor_type: "admin", occurred_at: Time.utc(2026, 1, 1))
    expect { BillingEvent.where(id: event.id).update_all(event_type: "clock.day_advanced") }
      .to raise_error(ActiveRecord::StatementInvalid, /append-only/)
  end

  it "keeps the demo user and open sessions when it reseeds, and wipes them on a bare wipe" do
    allow(Demo::Seed).to receive(:call) # the seeding itself is covered by seed_spec
    user = Demo::User.ensure!
    user.sessions.create!(last_seen_at: Time.utc(2026, 10, 1))

    described_class.call

    expect([ User.count, Session.count ]).to eq([ 1, 1 ])

    described_class.call(reseed: false)

    expect([ User.count, Session.count ]).to eq([ 0, 0 ])
  end
end
