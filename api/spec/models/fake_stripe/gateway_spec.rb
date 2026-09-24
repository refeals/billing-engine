require "rails_helper"

RSpec.describe FakeStripe::Gateway do
  before { freeze_clock_at(Time.utc(2026, 10, 5, 9)) }

  let(:outbox) { FakeStripe::MockedWebhookEvent }

  it "creates customers with a cus_ id and reports it" do
    id = described_class.create_customer(name: "Studio Flow", email: "owner@flow.test")

    expect(id).to start_with("cus_")
    event = outbox.sole
    expect(event).to have_attributes(event_type: "customer.created", provider_object_id: id,
      provider_created_at: Time.utc(2026, 10, 5, 9))
    expect(event.payload.dig("data", "object")).to include("email" => "owner@flow.test")
  end

  it "attaches test cards, answering with the card details the token stands for" do
    card = described_class.attach_payment_method(customer: "cus_1", token: "pm_card_chargeDeclinedInsufficientFunds",
      exp_month: 12, exp_year: 2028)

    expect(card).to include(brand: "visa", last4: "9995")
    expect(card[:id]).to start_with("pm_")
    expect(outbox.sole.event_type).to eq("payment_method.attached")
  end

  it "refuses an unknown test card without emitting anything" do
    expect { described_class.attach_payment_method(customer: "cus_1", token: "pm_card_nope", exp_month: 1, exp_year: 2030) }
      .to raise_error(DomainError) { |error| expect(error.code).to eq("unknown_test_card") }
    expect(outbox.count).to eq(0)
  end

  it "reports subscriptions with Stripe-shaped Unix timestamps" do
    id = described_class.create_subscription(snapshot: {
      customer: "cus_1", plan: "studio", status: "trialing",
      current_period_start: Time.utc(2026, 10, 5), current_period_end: Time.utc(2026, 10, 19), trial_end: Time.utc(2026, 10, 19),
      cancel_at_period_end: false, canceled_at: nil
    })

    object = outbox.sole.payload.dig("data", "object")
    expect(object).to include("id" => id, "status" => "trialing", "plan" => { "id" => "studio" },
      "current_period_end" => Time.utc(2026, 10, 19).to_i, "canceled_at" => nil)
    expect(outbox.sole.provider_subscription_id).to eq(id)
  end

  it "reports a canceled subscription as deleted" do
    described_class.update_subscription("sub_1", snapshot: { customer: "cus_1", plan: "studio", status: "canceled" })

    expect(outbox.sole.event_type).to eq("customer.subscription.deleted")
  end

  # The fake's history is only an independent record if it never looks at ours.
  it "never reads or writes the engine's tables" do
    # Measures the provider alone; delivering to the engine's inbox is the "network", tested
    # in the dispatcher spec.
    allow(FakeStripe::Dispatcher).to receive(:schedule_flush)
    tables = []
    callback = lambda do |*, payload|
      next if payload[:name] == "SCHEMA" || payload[:sql].match?(/\A\s*(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/i)

      tables.concat(payload[:sql].scan(/(?:FROM|INTO|UPDATE|JOIN)\s+"?(\w+)"?/i).flatten)
    end

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      ActiveRecord::Base.transaction do
        described_class.create_customer(name: "A", email: "a@a.test")
        described_class.attach_payment_method(customer: "cus_1", token: "pm_card_visa", exp_month: 1, exp_year: 2030)
        described_class.create_subscription(snapshot: { customer: "cus_1", plan: "p", status: "active" })
        described_class.update_subscription("sub_1", snapshot: { customer: "cus_1", plan: "p", status: "paused" })
      end
    end

    # simulation_clock is the shared "wall clock" of the simulated world, not engine data.
    expect(tables.uniq - %w[simulation_clock]).to eq(%w[mocked_webhook_events])
  end
end
