require "rails_helper"

RSpec.describe Subscription do
  it "refuses a status change that bypasses the transition service" do
    subscription = create(:subscription)

    expect { subscription.update!(status: "canceled") }.to raise_error(Subscription::DirectStatusChangeError)
    expect(subscription.reload.status).to eq("active")
  end

  it "still allows other attribute updates" do
    subscription = create(:subscription)

    expect { subscription.update!(cancel_at_period_end: true) }.not_to raise_error
  end

  it "allows only one live subscription per customer, at the database level" do
    customer = create(:customer)
    create(:subscription, customer: customer)

    expect { create(:subscription, customer: customer) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "keeps canceled subscriptions out of that limit" do
    customer = create(:customer)
    create(:subscription, customer: customer, status: "canceled")

    expect { create(:subscription, customer: customer) }.not_to raise_error
  end

  describe "#allowed_actions" do
    it "offers cancellation and scheduling during a trial" do
      expect(build(:subscription, :trialing).allowed_actions).to eq(%w[cancel_now cancel_at_period_end change_plan])
    end

    it "offers pause only while no cancellation is scheduled" do
      expect(build(:subscription).allowed_actions).to eq(%w[cancel_now cancel_at_period_end pause change_plan])
      expect(build(:subscription, cancel_at_period_end: true).allowed_actions).to eq(%w[cancel_now undo_cancel])
    end

    it "offers resume when paused and nothing when canceled" do
      expect(build(:subscription, :paused).allowed_actions).to eq(%w[resume cancel_now])
      expect(build(:subscription, status: "canceled").allowed_actions).to eq([])
    end
  end
end
