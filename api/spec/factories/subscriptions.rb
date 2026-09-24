FactoryBot.define do
  # Inserts a subscription in a given state directly, for specs that start mid-lifecycle.
  # Flows under test go through Subscriptions::Create / Transition instead.
  factory :subscription do
    customer
    plan
    sequence(:provider_subscription_id) { |n| "sub_test#{n}" }
    status { "active" }
    current_period_start { Time.utc(2026, 10, 1) }
    current_period_end { Time.utc(2026, 11, 1) }

    trait :trialing do
      status { "trialing" }
      trial_ends_at { current_period_end }
    end

    trait :paused do
      status { "paused" }
      paused_at { Time.utc(2026, 10, 5) }
    end
  end
end
