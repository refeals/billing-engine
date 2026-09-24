module Api
  module V1
    module Simulator
      class ClocksController < BaseController
        def show
          render json: ClockSerializer.new(BillingClock.now)
        end

        def advance
          result = BillingClock.advance!(days: params.require(:days))

          render json: ClockSerializer.new(result[:now]).as_json.merge(
            ticks_run: result[:ticks_run],
            tick_report: result[:tick_report]
          )
        end

        def reset
          render json: ClockSerializer.new(BillingClock.reset!)
        end
      end
    end
  end
end
