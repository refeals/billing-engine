module Api
  module V1
    class DunningCasesController < BaseController
      include Pagination

      # `status=open` for the cases still running, `status=closed` for the finished ones.
      def index
        scope = DunningCase.includes(:invoice, subscription: :customer).newest_first
        case params[:status]
        when "open" then scope = scope.open
        when "closed" then scope = scope.where.not(status: "open")
        when nil, "" then nil
        else raise DomainError.new("status must be open or closed", code: "invalid_filter", details: { status: params[:status] })
        end
        cases, meta = paginate(scope)

        render json: { data: cases.map { |dunning_case| DunningCaseSerializer.new(dunning_case) }, meta: meta }
      end

      def show
        render json: DunningCaseSerializer.new(DunningCase.find(params[:id]), detail: true)
      end
    end
  end
end
