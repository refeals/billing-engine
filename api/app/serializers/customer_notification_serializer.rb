class CustomerNotificationSerializer
  def initialize(notification)
    @notification = notification
  end

  def as_json(*)
    @notification.slice(:id, :kind, :subject, :body, :dunning_case_id).merge(sent_at: @notification.sent_at.iso8601)
  end
end
