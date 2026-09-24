FactoryBot.define do
  factory :payment_method do
    customer
    sequence(:provider_payment_method_id) { |n| "pm_test#{n}" }
    test_card_token { "pm_card_visa" }
    brand { "visa" }
    last4 { "4242" }
    exp_month { 12 }
    exp_year { 2030 }
    is_default { false }
  end
end
