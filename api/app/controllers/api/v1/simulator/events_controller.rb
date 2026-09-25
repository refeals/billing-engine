module Api
  module V1
    module Simulator
      # The fake provider's outbox, plus the controls a demo needs: make the provider report
      # something (possibly disagreeing with the engine), lose an event, or send it twice.
      class EventsController < BaseController
        include Pagination

        MANUAL_TYPES = %w[customer.subscription.updated customer.subscription.deleted].freeze

        def index
          scope = FakeStripe::MockedWebhookEvent.newest_first
          scope = scope.where(delivery_status: delivery_status_filter) if params[:delivery_status].present?
          scope = scope_to_scenario_run(scope) if params[:scenario_run_id].present?
          events, meta = paginate(scope)

          render json: { data: serialize(events), meta: meta }
        end

        def create
          subscription = Subscription.includes(:customer, :plan).find(params.require(:subscription_id))
          snapshot = subscription.provider_snapshot
          snapshot = snapshot.merge(status: status_override) if params[:status].present?

          # The fake itself, not PaymentGateway: making the provider speak up is a simulator
          # control, not something the engine could ask a real provider to do.
          event = FakeStripe::Gateway.emit_subscription_event(
            subscription.provider_subscription_id,
            snapshot: snapshot, type: event_type, delivery: delivery_mode, copies: copies
          )

          render json: serialize([ event.reload ]).first, status: :created
        end

        # Delivers a dropped event (the lost webhook finally arrives) or sends a delivered one
        # again (a duplicate).
        def deliver
          event = FakeStripe::MockedWebhookEvent.find(params[:id])
          if event.pending?
            raise DomainError.new("Event #{event.event_id} is already waiting for delivery", code: "delivery_pending")
          end

          FakeStripe::Dispatcher.redeliver(event)
          render json: serialize([ event.reload ]).first
        end

        private

        # The clock is shared, so other subscriptions renew during a scenario; only the events of
        # the scenario's own subscription belong to its run.
        def scope_to_scenario_run(scope)
          scenario_run = ScenarioRun.find(params[:scenario_run_id])
          scope.where(scenario_run_id: scenario_run.id, provider_subscription_id: scenario_run.subscription&.provider_subscription_id)
        end

        def serialize(events)
          inbox_ids = MockedWebhookEventSerializer.inbox_ids_for(events)
          events.map { |event| MockedWebhookEventSerializer.new(event, inbox_ids: inbox_ids).as_json }
        end

        def event_type
          type = params.require(:type)
          return type if MANUAL_TYPES.include?(type)

          invalid!(:type, "must be one of #{MANUAL_TYPES.join(', ')}")
        end

        def status_override
          return params[:status] if SubscriptionStateMachine::STATES.include?(params[:status])

          invalid!(:status, "must be one of #{SubscriptionStateMachine::STATES.join(', ')}")
        end

        def delivery_mode
          mode = params[:delivery].presence || "deliver"
          return mode if %w[deliver drop].include?(mode)

          invalid!(:delivery, "must be deliver or drop")
        end

        def copies
          value = Integer((params[:copies].presence || 1).to_s, 10, exception: false)
          return value if value&.between?(1, 5)

          invalid!(:copies, "must be a whole number between 1 and 5")
        end

        def delivery_status_filter
          return params[:delivery_status] if FakeStripe::MockedWebhookEvent::DELIVERY_STATUSES.include?(params[:delivery_status])

          raise DomainError.new("delivery_status must be one of #{FakeStripe::MockedWebhookEvent::DELIVERY_STATUSES.join(', ')}",
            code: "invalid_filter", details: { delivery_status: params[:delivery_status] })
        end

        def invalid!(name, reason)
          raise DomainError.new("#{name} #{reason}", code: "invalid_event", details: { name => params[name] })
        end
      end
    end
  end
end
