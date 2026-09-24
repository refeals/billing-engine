require "rails_helper"

RSpec.describe Plans::Archive do
  before { freeze_clock_at(Time.utc(2026, 10, 1, 12)) }

  it "archives the plan at simulated time and audits it" do
    plan = create(:plan)

    described_class.call(plan)

    expect(plan.reload.archived_at).to eq(Time.utc(2026, 10, 1, 12))
    expect(BillingEvent.of_type("plan.archived").sole.subject).to eq(plan)
  end

  it "refuses to archive twice" do
    plan = create(:plan, archived_at: Time.utc(2026, 9, 1))

    expect { described_class.call(plan) }
      .to raise_error(DomainError) { |error| expect(error.code).to eq("plan_already_archived") }
  end
end
