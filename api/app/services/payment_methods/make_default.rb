module PaymentMethods
  class MakeDefault < ApplicationService
    def initialize(payment_method)
      @payment_method = payment_method
    end

    def call
      ActiveRecord::Base.transaction do
        @payment_method.customer.lock!
        @payment_method.reload
        swap_default unless @payment_method.is_default?
        @payment_method
      end
    end

    private

    def swap_default
      previous_default = @payment_method.customer.default_payment_method
      # Unset first: the partial unique index allows only one default at any moment.
      previous_default&.update!(is_default: false)
      @payment_method.update!(is_default: true)

      Dunning::RetryAfterCardUpdate.call(@payment_method.customer)
      Audit.record(event_type: "payment_method.default_changed", subject: @payment_method,
        before: { default_payment_method_id: previous_default&.provider_payment_method_id },
        after: { default_payment_method_id: @payment_method.provider_payment_method_id })
    end
  end
end
