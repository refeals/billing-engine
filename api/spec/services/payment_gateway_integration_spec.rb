require "rails_helper"

# The engine and the fake provider talking end to end: gateway calls, the outbox, delivery
# after commit and the inbox observing what the provider reports.
RSpec.describe "Engine and provider in sync" do
  let(:outbox) { FakeStripe::MockedWebhookEvent }

  before { freeze_clock_at(Time.utc(2026, 10, 5)) }

  it "gets its ids from the provider and hears back about everything it created" do
    customer = Customers::Create.call(name: "Studio Flow", email: "owner@flow.test")
    card = PaymentMethods::Attach.call(customer, token: "pm_card_visa", exp_month: 12, exp_year: 2028)
    subscription = Subscriptions::Create.call(customer: customer, plan: create(:plan, trial_days: 14))

    expect(outbox.order(:id).pluck(:event_type, :provider_object_id)).to eq([
      [ "customer.created", customer.provider_customer_id ],
      [ "payment_method.attached", card.provider_payment_method_id ],
      [ "customer.subscription.created", subscription.provider_subscription_id ]
    ])
    expect(outbox.pluck(:delivery_status)).to all(eq("delivered"))
    expect(WebhookEvent.find_by!(event_type: "customer.subscription.created").processing_status).to eq("processed")
  end

  it "pushes committed status changes, and the provider's report matches the engine" do
    subscription = create(:subscription, customer: create(:customer, provider_customer_id: "cus_1"))

    Subscriptions::Pause.call(subscription, lock_version: subscription.lock_version)

    event = outbox.sole
    expect(event.event_type).to eq("customer.subscription.updated")
    expect(event.payload.dig("data", "object", "status")).to eq("paused")
    observed = BillingEvent.of_type("provider.subscription_observed").sole
    expect(observed.data["context"]).to include("provider_status" => "paused", "engine_status" => "paused", "matches" => true)
  end

  it "reports a cancellation as deleted" do
    subscription = create(:subscription)

    Subscriptions::Cancel.call(subscription, lock_version: subscription.lock_version, at_period_end: false)

    expect(outbox.sole.event_type).to eq("customer.subscription.deleted")
  end

  it "tells the provider nothing about a change that rolled back" do
    subscription = create(:subscription)

    ActiveRecord::Base.transaction do
      Subscriptions::Pause.call(subscription, lock_version: subscription.lock_version)
      raise ActiveRecord::Rollback
    end

    expect(outbox.count).to eq(0)
  end

  it "keeps a committed change and records the failure when the provider can't be told" do
    subscription = create(:subscription)
    allow(FakeStripe::Gateway).to receive(:update_subscription).and_raise("provider unreachable")

    expect { Subscriptions::Pause.call(subscription, lock_version: subscription.lock_version) }.not_to raise_error

    expect(subscription.reload.status).to eq("paused")
    failure = BillingEvent.of_type("provider.sync_failed").sole
    expect(failure).to have_attributes(subscription_id: subscription.id, actor_type: "admin")
    expect(failure.data["context"]).to include("message" => "provider unreachable", "status" => "paused")
  end

  it "doesn't echo back what it observed from the provider" do
    subscription = create(:subscription)
    FakeStripe::Gateway.emit_subscription_event(subscription.provider_subscription_id, snapshot: subscription.provider_snapshot)

    expect(outbox.count).to eq(1)
  end

  it "doesn't reach the provider when local checks refuse the request" do
    customer = create(:customer)

    expect { PaymentMethods::Attach.call(customer, token: "pm_card_visa", exp_month: 1, exp_year: 2020) }
      .to raise_error(DomainError, /expired/)
    expect { Customers::Create.call(name: "Dup", email: customer.email) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(outbox.count).to eq(0)
  end
end
