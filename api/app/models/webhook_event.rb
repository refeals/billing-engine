class WebhookEvent < ApplicationRecord
  STATUSES = %w[received processed failed skipped_stale ignored_unhandled].freeze
  # Done for good: a new delivery of the same event is a duplicate.
  TERMINAL_STATUSES = %w[processed skipped_stale ignored_unhandled].freeze
  # Not done yet: a redelivery or a manual reprocess may run it (again).
  REPROCESSABLE_STATUSES = %w[received failed].freeze

  enum :processing_status, STATUSES.index_by(&:itself), validate: true

  has_many :billing_events, -> { order(:id) }, inverse_of: false

  validates :provider_event_id, :event_type, :provider_object_id, :provider_created_at, :received_at, presence: true

  scope :newest_first, -> { order(received_at: :desc, id: :desc) }

  def terminal?
    TERMINAL_STATUSES.include?(processing_status)
  end

  def reprocessable?
    REPROCESSABLE_STATUSES.include?(processing_status)
  end
end
