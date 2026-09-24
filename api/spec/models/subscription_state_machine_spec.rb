require "rails_helper"

RSpec.describe SubscriptionStateMachine do
  origins = [ nil, *described_class::STATES ]

  # Generated from the constant: adding a state or an edge without thinking about every
  # other pair makes this spec fail.
  origins.each do |from|
    described_class::STATES.each do |to|
      reasons = described_class::TRANSITIONS.fetch(from, {})[to]

      if reasons
        reasons.each do |reason|
          it "allows #{from || '(new)'} → #{to} for #{reason}" do
            expect(described_class.allowed?(from, to, reason)).to be(true)
          end
        end

        it "refuses #{from || '(new)'} → #{to} for an unrelated reason" do
          expect(described_class.allowed?(from, to, "made_up_reason")).to be(false)
        end
      else
        it "refuses #{from || '(new)'} → #{to} for any reason, reconciliation included" do
          [ "customer_requested", described_class::RECONCILIATION_REASON ].each do |reason|
            expect(described_class.allowed?(from, to, reason)).to be(false)
          end
        end
      end
    end
  end

  it "accepts a reconciliation correction on an existing edge" do
    expect(described_class.allowed?("active", "past_due", "reconciliation_correction")).to be(true)
  end

  it "treats canceled as terminal" do
    expect(described_class.targets_from("canceled")).to be_empty
  end

  it "explains a refused move" do
    expect { described_class.assert!("canceled", "active", "customer_requested") }
      .to raise_error(InvalidTransitionError) { |error|
        expect(error.details).to include(from: "canceled", to: "active", allowed: {})
      }
  end
end
