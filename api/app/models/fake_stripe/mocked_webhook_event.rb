module FakeStripe
  class MockedWebhookEvent < ApplicationRecord
    self.table_name = "mocked_webhook_events"

    DELIVERY_STATUSES = %w[pending delivered dropped].freeze

    enum :delivery_status, DELIVERY_STATUSES.index_by(&:itself), validate: true
    enum :delivery_mode, %w[deliver drop].index_by(&:itself), validate: true, prefix: :mode

    validates :event_id, :event_type, :api_version, :provider_object_id, :provider_created_at, presence: true
    validates :copies, numericality: { only_integer: true, in: 1..5 }

    scope :newest_first, -> { order(id: :desc) }
  end
end
