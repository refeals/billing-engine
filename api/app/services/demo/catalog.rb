module Demo
  # The plans the demo studios subscribe to. Seeds and scenarios both use them, found or
  # created by code, so scenarios work with or without seed data.
  module Catalog
    PLANS = [
      { code: "starter", name: "Starter", amount_cents: 2_900, interval: "month", trial_days: 14 },
      { code: "studio", name: "Studio", amount_cents: 5_900, interval: "month", trial_days: 0 },
      { code: "studio_pro", name: "Studio Pro", amount_cents: 9_900, interval: "month", trial_days: 0 },
      { code: "studio_annual", name: "Studio Annual", amount_cents: 59_000, interval: "year", trial_days: 0 }
    ].freeze

    # Returns { "starter" => plan, … }.
    def self.ensure!
      PLANS.to_h { |attributes| [ attributes[:code], Plan.find_by(code: attributes[:code]) || Plans::Create.call(attributes) ] }
    end
  end
end
