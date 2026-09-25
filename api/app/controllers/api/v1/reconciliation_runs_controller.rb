module Api
  module V1
    class ReconciliationRunsController < BaseController
      include Pagination

      def index
        runs, meta = paginate(ReconciliationRun.newest_first)
        render json: { data: runs.map { |run| ReconciliationRunSerializer.new(run) }, meta: meta }
      end

      def show
        render json: ReconciliationRunSerializer.new(ReconciliationRun.find(params[:id]), detail: true)
      end

      # Synchronous: the dataset is small, and the operator wants the answer on screen.
      def create
        subscription = Subscription.find(params[:subscription_id]) if params[:subscription_id].present?
        run = Reconciliation::Run.call(triggered_by: "admin", subscription: subscription)
        render json: ReconciliationRunSerializer.new(run, detail: true), status: :created
      end
    end
  end
end
