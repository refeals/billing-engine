module Api
  module V1
    # The provider's endpoint. Not a BaseController: requests come from the provider, not the
    # operator, and retries are deduplicated by event id rather than by Idempotency-Key.
    class WebhooksController < ApplicationController
      # 200 tells the provider "done, stop sending"; that includes duplicates and events we
      # deliberately ignore. 500 means "failed, send it again", which is how a failed
      # handler gets retried.
      def stripe
        result = Webhooks::Ingest.call(raw_body: request.raw_post, headers: request.headers)

        render status: result.status == :failed ? :internal_server_error : :ok,
          json: { status: result.status, webhook_event_id: result.webhook_event.id }
      end
    end
  end
end
