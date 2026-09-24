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
        ensure_no_live_subscription!

        # The provider hands out the subscription id, so it is created there before our
        # insert; the checks above run first, so a refused create never reaches it.
        subscription = Subscription.new(base_attributes)
        subscription.provider_subscription_id = PaymentGateway.current.create_subscription(
          snapshot: subscription.provider_snapshot.merge(status: initial_status)
        )
        Transition.call(subscription, to: initial_status, reason: "subscription_created")
        # Without a trial the first period is billed right away. The subscription is active
        # meanwhile; if the payment fails, the webhook moves it to past_due (there is no
        # separate "incomplete" state).
        unless trial?
          Invoices::Issue.call(subscription: subscription, billing_reason: "subscription_create",
            period_start: subscription.current_period_start, period_end: subscription.current_period_end)
        end
        subscription
      end
    rescue ActiveRecord::RecordNotUnique
      # The partial unique index caught a concurrent create the check above couldn't see.
      raise DomainError.new("#{@customer.name} already has a live subscription", code: "customer_already_subscribed")
    end

    private

    def ensure_no_live_subscription!
      return unless @customer.subscriptions.live.exists?

      raise DomainError.new("#{@customer.name} already has a live subscription", code: "customer_already_subscribed")
    end

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
    # the first paid period starts now.
    def base_attributes
      period_end = trial? ? now + @plan.trial_days.days : PlanPeriod.advance(now, @plan)

      {
        customer: @customer, plan: @plan,
        current_period_start: now, current_period_end: period_end,
        trial_ends_at: (period_end if trial?)
      }
    end
  end
end
