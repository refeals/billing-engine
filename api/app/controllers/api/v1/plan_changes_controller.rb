module Api
  module V1
    class PlanChangesController < BaseController
      def index
        changes = subscription.plan_changes.includes(:from_plan, :to_plan).newest_first
        render json: { data: changes.map { |change| PlanChangeSerializer.new(change) } }
      end

      # What the change would do, without doing it.
      def preview
        quote = PlanChanges::Quote.new(subscription: subscription, to_plan: target_plan, strategy: params[:strategy])
        render json: PlanChangeQuoteSerializer.new(quote)
      end

      # Prorated changes need the preview's quote_token, which carries the proration date the
      # server computed; a client can't pick its own date.
      def create
        proration_date = if params[:quote_token].present?
          PlanChanges::QuoteToken.proration_date!(params[:quote_token], subscription: subscription,
            to_plan: target_plan, strategy: params[:strategy])
        end
        plan_change = PlanChanges::Apply.call(subscription, lock_version: lock_version, to_plan: target_plan,
          strategy: params[:strategy], proration_date: proration_date)
        render json: PlanChangeSerializer.new(plan_change), status: :created
      end

      # The change record's own status guards this: only a scheduled change can be canceled.
      def cancel
        plan_change = subscription.plan_changes.find(params[:id])
        render json: PlanChangeSerializer.new(PlanChanges::CancelScheduled.call(plan_change, reason: "operator_canceled"))
      end

      private

      def subscription
        @subscription ||= Subscription.includes(:plan, :customer).find(params[:subscription_id])
      end

      def target_plan
        Plan.find(params.require(:plan_id))
      end

      def lock_version
        value = Integer(params.require(:lock_version).to_s, 10, exception: false)
        return value if value

        raise DomainError.new("lock_version must be a whole number", code: "invalid_lock_version")
      end
    end
  end
end
