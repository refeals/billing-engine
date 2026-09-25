module Api
  module V1
    class SubscriptionsController < BaseController
      include Pagination

      def index
        scope = Subscription.includes(:customer, :plan).order(id: :desc)
        scope = scope.with_status(status_filter) if params[:status].present?
        scope = scope.search(params[:q]) if params[:q].present?
        subscriptions, meta = paginate(scope)

        render json: { data: subscriptions.map { |subscription| SubscriptionSerializer.new(subscription) }, meta: meta }
      end

      def show
        render json: SubscriptionSerializer.new(subscription, detail: true)
      end

      def create
        created = Subscriptions::Create.call(
          customer: Customer.find(params.require(:customer_id)),
          plan: Plan.find(params.require(:plan_id))
        )
        render json: SubscriptionSerializer.new(created, detail: true), status: :created
      end

      def cancel
        at_period_end = ActiveModel::Type::Boolean.new.cast(params[:at_period_end]) || false
        run(Subscriptions::Cancel, at_period_end: at_period_end)
      end

      def undo_cancel
        run(Subscriptions::UndoCancel)
      end

      def pause
        run(Subscriptions::Pause, resumes_at: resume_date)
      end

      def resume
        run(Subscriptions::Resume)
      end

      def state_transitions
        render json: { data: subscription.state_transitions.map { |transition| SubscriptionStateTransitionSerializer.new(transition) } }
      end

      private

      def subscription
        @subscription ||= Subscription.includes(:customer, :plan).find(params[:id])
      end

      def run(action, **options)
        render json: SubscriptionSerializer.new(action.call(subscription, lock_version: lock_version, **options), detail: true)
      end

      # Required on every change: it is how the API knows which version the operator saw.
      def lock_version
        value = Integer(params.require(:lock_version).to_s, 10, exception: false)
        return value if value

        raise DomainError.new("lock_version must be a whole number", code: "invalid_lock_version")
      end

      def resume_date
        return if params[:resumes_at].blank?

        Date.iso8601(params[:resumes_at].to_s).in_time_zone
      rescue Date::Error
        raise DomainError.new("resumes_at must be a date in YYYY-MM-DD format", code: "invalid_resume_date")
      end

      def status_filter
        return params[:status] if SubscriptionStateMachine::STATES.include?(params[:status])

        raise DomainError.new("status must be one of #{SubscriptionStateMachine::STATES.join(', ')}",
          code: "invalid_filter", details: { status: params[:status] })
      end
    end
  end
end
