# A signed-in browser. Expiry is measured in real time, not simulated billing time: moving
# the demo's clock forward a month must not sign the operator out.
class Session < ApplicationRecord
  EXPIRES_IN = 7.days
  # Writing last_seen_at on every request would make every read a write.
  TOUCH_EVERY = 1.minute

  belongs_to :user

  scope :expired, -> { where(created_at: ...wall_clock_now - EXPIRES_IN) }

  def self.wall_clock_now
    Time.now.utc # rubocop:disable Billing/DirectTimeAccess -- sessions live in real time
  end

  def expired?
    created_at < self.class.wall_clock_now - EXPIRES_IN
  end

  def touch_last_seen
    now = self.class.wall_clock_now
    update_column(:last_seen_at, now) if last_seen_at < now - TOUCH_EVERY
  end
end
