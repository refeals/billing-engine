FactoryBot.define do
  factory :billing_event do
    event_type { "clock.day_advanced" }
    actor_type { "admin" }
    data { {} }
    occurred_at { Time.zone.parse("2026-10-01 12:00:00") }
  end
end
