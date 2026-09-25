module Dunning
  # Writes what would be emailed to the customer. No email is sent in this project.
  module Notify
    TEMPLATES = {
      "payment_failed" => [ "Your payment didn't go through",
        "We couldn't charge %<amount>s for invoice %<invoice>s. We'll try again in 3 days; updating your card now avoids any interruption." ],
      "payment_retry" => [ "We're retrying your payment",
        "We're trying again to charge %<amount>s for invoice %<invoice>s." ],
      "access_suspended" => [ "Your access is suspended",
        "Invoice %<invoice>s (%<amount>s) is still unpaid, so access is suspended. Paying it restores access right away." ],
      "subscription_canceled" => [ "Your subscription was canceled",
        "Invoice %<invoice>s (%<amount>s) stayed unpaid for 14 days, so the subscription was canceled." ],
      "payment_recovered" => [ "Payment received, thank you",
        "Invoice %<invoice>s (%<amount>s) is paid and your subscription is active again." ]
    }.freeze

    def self.call(dunning_case, kind, step: nil)
      subject, body = TEMPLATES.fetch(kind)
      invoice = dunning_case.invoice
      amount = ActiveSupport::NumberHelper.number_to_currency(BigDecimal(invoice.total_cents) / 100)

      CustomerNotification.create!(
        customer_id: invoice.customer_id, kind: kind, subject: subject,
        body: format(body, amount: amount, invoice: invoice.number),
        dunning_case: dunning_case, dunning_step: step, sent_at: BillingClock.now
      )
    end
  end
end
