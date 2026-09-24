FactoryBot.define do
  factory :customer do
    sequence(:name) { |n| "Studio Flow #{n}" }
    sequence(:email) { |n| "owner#{n}@studioflow.test" }
    sequence(:provider_customer_id) { |n| "cus_test#{n}" }
  end
end
