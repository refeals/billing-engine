module Api
  module V1
    class NotificationsController < BaseController
      include Pagination

      def index
        notifications, meta = paginate(Customer.find(params[:customer_id]).then { |customer| CustomerNotification.where(customer: customer).newest_first })
        render json: { data: notifications.map { |notification| CustomerNotificationSerializer.new(notification) }, meta: meta }
      end
    end
  end
end
