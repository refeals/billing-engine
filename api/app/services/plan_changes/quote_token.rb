module PlanChanges
  # A signed receipt of a preview. Applying a prorated change needs the preview's
  # proration_date, but a date sent by the client could be backdated to the start of the
  # period (a larger credit on a downgrade, a larger charge on an upgrade). The token lets the
  # client send back only a date the server itself issued, for that subscription and plan.
  module QuoteToken
    PURPOSE = :plan_change_quote

    class << self
      def issue(quote)
        verifier.generate(
          { "subscription_id" => quote.subscription.id, "to_plan_id" => quote.to_plan.id,
            "strategy" => quote.strategy, "proration_date" => quote.proration_date&.iso8601 },
          purpose: PURPOSE
        )
      end

      # Returns the proration_date the preview used, after checking the token belongs to this
      # exact change.
      def proration_date!(token, subscription:, to_plan:, strategy:)
        data = verifier.verified(token.to_s, purpose: PURPOSE)
        matches = data && data["subscription_id"] == subscription.id && data["to_plan_id"] == to_plan.id &&
          data["strategy"] == (strategy.presence || "immediate")
        raise DomainError.new("quote_token doesn't match this plan change; preview again", code: "invalid_quote_token") unless matches

        data["proration_date"]
      end

      private

      def verifier
        Rails.application.message_verifier(PURPOSE)
      end
    end
  end
end
