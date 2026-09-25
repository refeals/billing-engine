require "rails_helper"

RSpec.describe Reconciliation::ProjectExpectedState do
  def event(type, object, id: "evt_#{SecureRandom.hex(3)}")
    { event_id: id, type: type, object: object.deep_stringify_keys }
  end

  def snapshot(status, id: nil, plan: "basic", period_end: 1_000)
    event("customer.subscription.updated", { id: "sub_1", status: status, plan: { id: plan }, current_period_end: period_end },
      **{ id: id }.compact)
  end

  it "takes subscription fields from the last snapshot, with the event as evidence" do
    result = described_class.call([ snapshot("trialing"), snapshot("active", id: "evt_last", plan: "pro", period_end: 2_000) ])

    expect(result.subscription).to include(status: "active", plan: "pro", current_period_end: 2_000)
    expect(result.subscription[:evidence][:status]).to eq([ "evt_last" ])
  end

  it "applies the payment rule: paid invoices activate, failed ones make past_due" do
    events = [ snapshot("active"), event("invoice.payment_failed", { id: "in_1" }, id: "evt_failed") ]
    expect(described_class.call(events).subscription).to include(status: "past_due")

    events << event("invoice.paid", { id: "in_1", amount_paid: 4900 }, id: "evt_paid")
    result = described_class.call(events)
    expect(result.subscription[:status]).to eq("active")
    expect(result.subscription[:evidence][:status]).to eq([ "evt_paid" ])
    expect(result.invoices["in_1"]).to include(paid: true, amount_paid: 4900)
  end

  it "doesn't let a payment revive a canceled or paused subscription" do
    %w[canceled paused].each do |status|
      result = described_class.call([ snapshot(status), event("invoice.paid", { id: "in_1", amount_paid: 100 }) ])
      expect(result.subscription[:status]).to eq(status)
    end
  end

  it "follows refunds through the charge that paid the invoice" do
    result = described_class.call([
      event("charge.succeeded", { id: "ch_1", invoice: "in_1" }),
      event("invoice.paid", { id: "in_1", amount_paid: 4900 }),
      event("charge.refunded", { id: "ch_1", amount_refunded: 1500 }),
      event("charge.refunded", { id: "ch_1", amount_refunded: 2500 })
    ])

    expect(result.invoices["in_1"][:amount_refunded]).to eq(2500)
  end
end
