FactoryBot.define do
  factory :plan do
    sequence(:code) { |n| "studio_#{n}" }
    name { "Studio" }
    amount_cents { 4900 }
    interval { "month" }
    trial_days { 14 }
  end
end
