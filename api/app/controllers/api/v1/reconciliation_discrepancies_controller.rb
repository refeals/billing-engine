module Api
  module V1
    class ReconciliationDiscrepanciesController < BaseController
      include Pagination

      STATUSES = %w[open resolved acknowledged cleared].freeze

      def index
        scope = ReconciliationDiscrepancy.includes(subscription: :customer).newest_first
        scope = scope.where(status: status_filter) if params[:status].present?
        scope = scope.where(subscription_id: params[:subscription_id]) if params[:subscription_id].present?
        discrepancies, meta = paginate(scope)

        render json: { data: discrepancies.map { |discrepancy| ReconciliationDiscrepancySerializer.new(discrepancy) }, meta: meta }
      end

      def resolve
        discrepancy = ReconciliationDiscrepancy.find(params[:id])
        Reconciliation::Resolve.call(discrepancy, strategy: params.require(:strategy), note: params[:note])
        render json: ReconciliationDiscrepancySerializer.new(discrepancy.reload)
      end

      private

      def status_filter
        return params[:status] if STATUSES.include?(params[:status])

        raise DomainError.new("status must be one of #{STATUSES.join(', ')}", code: "invalid_filter",
          details: { status: params[:status] })
      end
    end
  end
end
