class IdempotencyKey < ApplicationRecord
  validates :key, presence: true, uniqueness: true, length: { maximum: 255 }
  validates :request_fingerprint, presence: true

  def completed?
    response_status.present?
  end
end
