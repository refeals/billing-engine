module Customers
  class Create < ApplicationService
    def initialize(name:, email:)
      @name = name
      @email = email
    end

    def call
      ActiveRecord::Base.transaction do
        customer = Customer.create!(name: @name, email: @email,
          provider_customer_id: FakeStripe::ProviderIds.generate("cus"))
        Audit.record(event_type: "customer.created", subject: customer,
          after: customer.slice(:name, :email, :provider_customer_id))
        customer
      end
    end
  end
end
