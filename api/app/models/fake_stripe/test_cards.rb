module FakeStripe
  # Stripe test-mode cards: the token decides how the provider answers a charge, so a demo
  # can pick "a card that will be declined" without any real card data.
  module TestCards
    Card = Data.define(:token, :brand, :last4, :behavior, :description)

    CATALOG = [
      Card.new("pm_card_visa", "visa", "4242", "succeeds", "Always succeeds"),
      Card.new("pm_card_mastercard", "mastercard", "4444", "succeeds", "Always succeeds"),
      Card.new("pm_card_chargeDeclined", "visa", "0002", "card_declined", "Always declined"),
      Card.new("pm_card_chargeDeclinedInsufficientFunds", "visa", "9995", "insufficient_funds",
        "Declined for insufficient funds"),
      Card.new("pm_card_chargeDeclinedExpiredCard", "visa", "0069", "expired_card",
        "Declined as expired, whatever the expiry date"),
      Card.new("pm_card_succeedsAfterFailures_2", "visa", "3220", "succeeds_after_failures",
        "Declined twice, then succeeds (models a customer fixing their card)"),
      # Charges go through; refunds to it fail, like Stripe's refund-failure test card.
      Card.new("pm_card_refundFail", "visa", "5126", "succeeds", "Charges succeed, refunds fail")
    ].index_by(&:token).freeze

    def self.all
      CATALOG.values
    end

    def self.fetch(token)
      CATALOG.fetch(token) do
        raise DomainError.new("Unknown test card #{token.inspect}", code: "unknown_test_card",
          details: { known: CATALOG.keys })
      end
    end
  end
end
