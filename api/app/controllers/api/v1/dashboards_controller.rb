module Api
  module V1
    class DashboardsController < BaseController
      def summary
        render json: Dashboard::Summary.call
      end
    end
  end
end
