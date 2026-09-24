module Api
  module V1
    class PaymentMethodsController < BaseController
      def create
        payment_method = PaymentMethods::Attach.call(
          customer,
          token: params.require(:test_card),
          exp_month: params[:exp_month],
          exp_year: params[:exp_year],
          make_default: params[:default]
        )
        render json: PaymentMethodSerializer.new(payment_method), status: :created
      end

      def make_default
        payment_method = customer.payment_methods.find(params[:id])
        render json: PaymentMethodSerializer.new(PaymentMethods::MakeDefault.call(payment_method))
      end

      private

      def customer
        @customer ||= Customer.find(params[:customer_id])
      end
    end
  end
end
