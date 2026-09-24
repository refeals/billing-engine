# Builds customers and subscriptions through the real services, so provider ids, outbox
# events and webhooks all exist as they would in the app.
module BillingHelpers
  def customer_with_card(token = "pm_card_visa", exp_month: 12, exp_year: 2030)
    customer = Customers::Create.call(name: "Studio #{SecureRandom.hex(3)}", email: "#{SecureRandom.hex(4)}@studio.test")
    PaymentMethods::Attach.call(customer, token: token, exp_month: exp_month, exp_year: exp_year) if token
    customer.reload
  end

  def subscribe(customer, trial_days: 0, amount_cents: 4900, interval: "month")
    plan = create(:plan, trial_days: trial_days, amount_cents: amount_cents, interval: interval)
    Subscriptions::Create.call(customer: customer, plan: plan).reload
  end

  # Advances in chunks the clock accepts (at most 30 days each) and sums the reports.
  def advance_days(days)
    report = Hash.new(0)
    while days.positive?
      chunk = [ days, BillingClock::MAX_ADVANCE_DAYS ].min
      BillingClock.advance!(days: chunk)[:tick_report].each { |counter, value| report[counter] += value }
      days -= chunk
    end
    report
  end
end

RSpec.configure do |config|
  config.include BillingHelpers
end
