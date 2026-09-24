module Api
  module V1
    class PlansController < BaseController
      include Pagination

      def index
        scope = include_archived? ? Plan.all : Plan.active
        plans, meta = paginate(scope.order(:amount_cents, :id))

        render json: { data: plans.map { |plan| PlanSerializer.new(plan) }, meta: meta }
      end

      def show
        render json: PlanSerializer.new(Plan.find(params[:id]))
      end

      def create
        plan = Plans::Create.call(params.permit(:code, :name, :amount_cents, :interval, :trial_days))
        render json: PlanSerializer.new(plan), status: :created
      end

      def archive
        render json: PlanSerializer.new(Plans::Archive.call(Plan.find(params[:id])))
      end

      private

      def include_archived?
        ActiveModel::Type::Boolean.new.cast(params[:include_archived])
      end
    end
  end
end
