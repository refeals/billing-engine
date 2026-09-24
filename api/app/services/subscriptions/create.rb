module Subscriptions
  class Create < ApplicationService
    def initialize(customer:, plan:)
      @customer = customer
      @plan = plan
    end

    def call
      if @plan.archived?
        raise DomainError.new("Plan #{@plan.code} is archived and can't take new subscribers", code: "plan_archived")
      end

      ActiveRecord::Base.transaction do
        if @customer.subscriptions.live.exists?
          raise DomainError.new("#{@customer.name} already has a live subscription", code: "customer_already_subscribed")
        end

        Transition.call(Subscription.new(base_attributes), to: initial_status, reason: "subscription_created")
      end
    rescue ActiveRecord::RecordNotUnique
      # The partial unique index caught a concurrent create the check above couldn't see.
      raise DomainError.new("#{@customer.name} already has a live subscription", code: "customer_already_subscribed")
    end

    private

    def now
      @now ||= BillingClock.now
    end

    def trial?
      @plan.trial_days.positive?
    end

    def initial_status
      trial? ? "trialing" : "active"
    end

    # During a trial the current period is the trial itself, as in Stripe. Without a trial
    # the first paid period starts now. Until plan 07 adds invoicing, that first period is
    # not charged.
    def base_attributes
      period_end = trial? ? now + @plan.trial_days.days : PlanPeriod.advance(now, @plan)

      {
        customer: @customer, plan: @plan,
        provider_subscription_id: FakeStripe::ProviderIds.generate("sub"),
        current_period_start: now, current_period_end: period_end,
        trial_ends_at: (period_end if trial?)
      }
    end
  end
end
