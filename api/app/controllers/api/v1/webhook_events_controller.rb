module Api
  module V1
    # The inbox as seen by the operator.
    class WebhookEventsController < BaseController
      include Pagination

      def index
        scope = WebhookEvent.newest_first
        scope = scope.where(processing_status: status_filter) if params[:status].present?
        scope = scope.where(event_type: params[:event_type]) if params[:event_type].present?
        events, meta = paginate(scope)

        render json: { data: events.map { |event| WebhookEventSerializer.new(event) }, meta: meta }
      end

      def show
        render json: WebhookEventSerializer.new(webhook_event, detail: true)
      end

      # Runs a failed (or never finished) event again. Anything already done is refused:
      # reprocessing it would apply its effects twice.
      def reprocess
        unless webhook_event.reprocessable?
          raise DomainError.new("Event #{webhook_event.provider_event_id} is already #{webhook_event.processing_status}",
            code: "already_processed", details: { processing_status: webhook_event.processing_status })
        end

        ActiveRecord::Base.transaction do
          Audit.record(event_type: "webhook.reprocess_requested", subject: webhook_event,
            context: { previous_status: webhook_event.processing_status, attempts: webhook_event.attempts })
        end
        result = Webhooks::ProcessEvent.call(webhook_event)

        render json: { status: result.status, webhook_event: WebhookEventSerializer.new(result.webhook_event.reload, detail: true) }
      end

      private

      def webhook_event
        @webhook_event ||= WebhookEvent.find(params[:id])
      end

      def status_filter
        return params[:status] if WebhookEvent::STATUSES.include?(params[:status])

        raise DomainError.new("status must be one of #{WebhookEvent::STATUSES.join(', ')}",
          code: "invalid_filter", details: { status: params[:status] })
      end
    end
  end
end
