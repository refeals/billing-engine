module Api
  module V1
    class BillingEventsController < BaseController
      include Pagination

      def index
        events, meta = paginate(filtered_events.newest_first)

        render json: {
          data: events.map { |event| BillingEventSerializer.new(event) },
          meta: meta.merge(event_types: BillingEvent.distinct.order(:event_type).pluck(:event_type))
        }
      end

      private

      def filtered_events
        scope = BillingEvent.all
        scope = scope.for_subscription(params[:subscription_id]) if params[:subscription_id].present?
        scope = scope.for_customer(params[:customer_id]) if params[:customer_id].present?
        scope = scope.of_type(params[:event_type]) if params[:event_type].present?
        scope = scope.by_actor(actor_type_filter) if params[:actor_type].present?
        scope = scope.occurred_from(date_filter(:from).beginning_of_day) if params[:from].present?
        scope = scope.occurred_to(date_filter(:to).end_of_day) if params[:to].present?
        scope
      end

      def actor_type_filter
        return params[:actor_type] if BillingEvent::ACTOR_TYPES.include?(params[:actor_type])

        raise invalid_filter(:actor_type, "must be one of #{BillingEvent::ACTOR_TYPES.join(', ')}")
      end

      # Filters are whole days (YYYY-MM-DD), inclusive on both ends.
      def date_filter(name)
        # to_s turns a malformed `from[]=...` (an Array) into a parse error, not a TypeError.
        Date.iso8601(params[name].to_s).in_time_zone
      rescue Date::Error
        raise invalid_filter(name, "must be a date in YYYY-MM-DD format")
      end

      def invalid_filter(name, reason)
        DomainError.new("#{name} #{reason}", code: "invalid_filter", details: { name => params[name] })
      end
    end
  end
end
