module Api
  module V1
    module Simulator
      # Wipes every table and reseeds the demo. Deliberately hard to trigger by accident: the
      # request has to say so explicitly.
      class ResetsController < BaseController
        def create
          unless params[:confirm] == "reset"
            raise DomainError.new('Resetting deletes all data; send { "confirm": "reset" } to proceed',
              code: "confirmation_required")
          end

          render json: Demo::Reset.call, status: :created
        end
      end
    end
  end
end
