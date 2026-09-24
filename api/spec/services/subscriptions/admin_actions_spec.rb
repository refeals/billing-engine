require "rails_helper"

RSpec.describe "Subscription admin actions" do
  let(:now) { Time.utc(2026, 10, 10) }
  let(:subscription) { create(:subscription) }

  before { freeze_clock_at(now) }

  def lock
    subscription.reload.lock_version
  end

  describe Subscriptions::Cancel do
    it "cancels now" do
      described_class.call(subscription, lock_version: lock, at_period_end: false)

      expect(subscription.reload).to have_attributes(status: "canceled", canceled_at: now, cancellation_reason: "customer_requested")
    end

    it "schedules a cancellation without changing the status" do
      described_class.call(subscription, lock_version: lock, at_period_end: true)

      expect(subscription.reload).to have_attributes(status: "active", cancel_at_period_end: true)
      expect(BillingEvent.of_type("subscription.cancellation_scheduled").count).to eq(1)
    end

    it "refuses to schedule twice" do
      described_class.call(subscription, lock_version: lock, at_period_end: true)

      expect { described_class.call(subscription, lock_version: lock, at_period_end: true) }
        .to raise_error(DomainError) { |error| expect(error.code).to eq("action_not_allowed") }
    end

    it "reports a stale screen as a conflict even when the action is no longer allowed" do
      stale_lock = lock
      Subscriptions::Cancel.call(subscription, lock_version: stale_lock, at_period_end: true)

      expect { described_class.call(subscription.reload, lock_version: stale_lock, at_period_end: true) }
        .to raise_error(ActiveRecord::StaleObjectError)
    end

    it "refuses to act on a version the operator never saw" do
      expect { described_class.call(subscription, lock_version: lock - 1, at_period_end: false) }
        .to raise_error(ActiveRecord::StaleObjectError)
      expect(subscription.reload.status).to eq("active")
    end
  end

  describe Subscriptions::UndoCancel do
    it "revokes a scheduled cancellation" do
      Subscriptions::Cancel.call(subscription, lock_version: lock, at_period_end: true)
      described_class.call(subscription, lock_version: lock)

      expect(subscription.reload.cancel_at_period_end).to be(false)
    end
  end

  describe Subscriptions::Pause do
    it "pauses with a resume date" do
      described_class.call(subscription, lock_version: lock, resumes_at: now + 5.days)

      expect(subscription.reload).to have_attributes(status: "paused", paused_at: now, resumes_at: now + 5.days)
    end

    it "refuses a resume date that is not in the future" do
      expect { described_class.call(subscription, lock_version: lock, resumes_at: now) }
        .to raise_error(DomainError) { |error| expect(error.code).to eq("invalid_resume_date") }
    end

    it "refuses to pause a subscription that is scheduled to cancel" do
      subscription.update!(cancel_at_period_end: true)

      expect { described_class.call(subscription, lock_version: lock) }
        .to raise_error(DomainError) { |error| expect(error.code).to eq("action_not_allowed") }
    end
  end

  describe Subscriptions::Resume do
    it "resumes and clears the pause" do
      Subscriptions::Pause.call(subscription, lock_version: lock, resumes_at: now + 5.days)
      described_class.call(subscription, lock_version: lock)

      expect(subscription.reload).to have_attributes(status: "active", paused_at: nil, resumes_at: nil)
    end
  end
end
