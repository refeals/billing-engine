module Api
  module V1
    class CustomersController < BaseController
      include Pagination

      def index
        scope = Customer.order(id: :desc)
        scope = scope.search(params[:q]) if params[:q].present?
        customers, meta = paginate(scope)

        render json: { data: customers.map { |customer| CustomerSerializer.new(customer) }, meta: meta }
      end

      def show
        customer = Customer.includes(:payment_methods).find(params[:id])
        render json: CustomerSerializer.new(customer, detail: true)
      end

      def create
        customer = Customers::Create.call(name: params[:name], email: params[:email])
        render json: CustomerSerializer.new(customer, detail: true), status: :created
      end
    end
  end
end
