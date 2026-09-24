module Api
  module V1
    module Simulator
      class TestCardsController < BaseController
        def index
          render json: { data: FakeStripe::TestCards.all.map(&:to_h) }
        end
      end
    end
  end
end
