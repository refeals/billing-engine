module PaymentMethods
  class Attach < ApplicationService
    PROVIDER_ATTRIBUTES = %i[provider_payment_method_id brand last4].freeze

    def initialize(customer, token:, exp_month:, exp_year:, make_default: false)
      @customer = customer
      @token = token
      @exp_month = exp_month
      @exp_year = exp_year
      @make_default = ActiveModel::Type::Boolean.new.cast(make_default)
    end

    def call
      # PaymentMethod.new, not payment_methods.build: a refused card must not linger in the
      # caller's association cache.
      payment_method = PaymentMethod.new(customer: @customer, test_card_token: @token,
        exp_month: @exp_month, exp_year: @exp_year)
      validate_before_calling_provider!(payment_method)

      ActiveRecord::Base.transaction do
        card = PaymentGateway.current.attach_payment_method(customer: @customer.provider_customer_id,
          token: @token, exp_month: payment_method.exp_month, exp_year: payment_method.exp_year)
        payment_method.assign_attributes(provider_payment_method_id: card[:id], brand: card[:brand], last4: card[:last4])

        @customer.lock!
        previous_default = @customer.default_payment_method
        # A customer's first card becomes the default, so renewals always have a card to charge.
        become_default = @make_default || previous_default.nil?
        previous_default&.update!(is_default: false) if become_default
        payment_method.is_default = become_default
        payment_method.save!

        # A new default card is the customer's way of fixing a failed payment.
        Dunning::RetryAfterCardUpdate.call(@customer) if become_default
        Audit.record(event_type: "payment_method.attached", subject: payment_method,
          after: payment_method.slice(:provider_payment_method_id, :brand, :last4, :exp_month, :exp_year, :is_default),
          context: { test_card_token: @token, behavior: payment_method.behavior })
        payment_method
      end
    end

    private

    # Local checks first (fields, expiry), so a card we would refuse never reaches the
    # provider. The provider-assigned fields are the only ones allowed to be missing here.
    def validate_before_calling_provider!(payment_method)
      payment_method.validate
      PROVIDER_ATTRIBUTES.each { |attribute| payment_method.errors.delete(attribute) }
      if payment_method.errors.include?(:test_card_token)
        FakeStripe::TestCards.fetch(@token) # raises unknown_test_card with the known tokens
      end
      raise ActiveRecord::RecordInvalid, payment_method if payment_method.errors.any?

      # Stripe refuses to attach a card that has already expired; so do we.
      return unless payment_method.expired?

      raise DomainError.new("This card expired at the end of #{@exp_month}/#{@exp_year}", code: "card_expired")
    end
  end
end
