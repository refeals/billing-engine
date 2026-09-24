module Subscriptions
  class Pause < AdminAction
    def call
      resumes_at = options[:resumes_at]
      if resumes_at && resumes_at <= now
        raise DomainError.new("The resume date must be in the future", code: "invalid_resume_date",
          details: { resumes_at: resumes_at.iso8601, now: now.iso8601 })
      end

      with_guards("pause") do
        Transition.call(subscription, to: "paused", reason: "customer_requested",
          attributes: { paused_at: now, resumes_at: resumes_at })
      end
    end
  end
end
