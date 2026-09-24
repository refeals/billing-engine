module Ticks
  # Ends pauses that were given a resume date.
  class ResumePaused
    def self.call(at:)
      due = Subscription.with_status("paused").where(resumes_at: ..at)

      resumed = due.find_each.count { |subscription| Subscriptions::Unpause.call(subscription, reason: "pause_ended") }

      { subscriptions_resumed: resumed }
    end
  end
end
