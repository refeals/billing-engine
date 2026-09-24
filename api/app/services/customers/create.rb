module Customers
  class Create < ApplicationService
    def initialize(name:, email:)
      @name = name
      @email = email
    end

    def call
      customer = Customer.new(name: @name, email: @email)
      validate_before_calling_provider!(customer)

      ActiveRecord::Base.transaction do
        # The provider hands out the id we store, so it is called before the insert (see
        # docs/06 on why inside the transaction).
        customer.provider_customer_id = PaymentGateway.current.create_customer(name: customer.name, email: customer.email)
        customer.save!
        Audit.record(event_type: "customer.created", subject: customer,
          after: customer.slice(:name, :email, :provider_customer_id))
        customer
      end
    end

    private

    # Everything except the provider id is checked before talking to the provider, so a
    # typo in the email doesn't leave a customer behind at the provider.
    def validate_before_calling_provider!(customer)
      customer.validate
      customer.errors.delete(:provider_customer_id)
      raise ActiveRecord::RecordInvalid, customer if customer.errors.any?
    end
  end
end
