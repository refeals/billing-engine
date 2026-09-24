module PaymentMethods
  class Attach < ApplicationService
    def initialize(customer, token:, exp_month:, exp_year:, make_default: false)
      @customer = customer
      @token = token
      @exp_month = exp_month
      @exp_year = exp_year
      @make_default = ActiveModel::Type::Boolean.new.cast(make_default)
    end

    def call
      card = FakeStripe::TestCards.fetch(@token)

      ActiveRecord::Base.transaction do
        @customer.lock!
        # PaymentMethod.new, not payment_methods.build: a refused card must not linger in the
        # caller's association cache after the transaction rolls back.
        payment_method = PaymentMethod.new(
          customer: @customer,
          provider_payment_method_id: FakeStripe::ProviderIds.generate("pm"),
          test_card_token: card.token, brand: card.brand, last4: card.last4,
          exp_month: @exp_month, exp_year: @exp_year
        )
        payment_method.validate!
        # Stripe refuses to attach a card that has already expired; so do we.
        if payment_method.expired?
          raise DomainError.new("This card expired at the end of #{@exp_month}/#{@exp_year}", code: "card_expired")
        end

        previous_default = @customer.default_payment_method
        # A customer's first card becomes the default, so renewals always have a card to charge.
        become_default = @make_default || previous_default.nil?
        previous_default&.update!(is_default: false) if become_default
        payment_method.is_default = become_default
        payment_method.save!

        Audit.record(event_type: "payment_method.attached", subject: payment_method,
          after: payment_method.slice(:provider_payment_method_id, :brand, :last4, :exp_month, :exp_year, :is_default),
          context: { test_card_token: card.token, behavior: card.behavior })
        payment_method
      end
    end
  end
end
