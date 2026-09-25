module Scenarios
  class ExpectationFailed < StandardError; end

  # A scenario is a short story told with the real services and ending in checks. Each step
  # is logged with the simulated time it ran at, so the Scenario Lab can replay what
  # happened; a failed check marks the run failed instead of raising at the API. The same
  # scenarios run in the test suite, so the demo can't silently rot.
  #
  # Scenarios move the shared simulated clock, which affects every subscription.
  class Base
    class << self
      attr_reader :key, :title, :description

      def scenario(key:, title:, description:)
        @key = key
        @title = title
        @description = description
      end

      def call
        new.run
      end
    end

    def run
      @run = ScenarioRun.create!(scenario_key: self.class.key, status: "running", started_at: BillingClock.now)
      @log = []
      Current.set(actor: "admin", scenario_run: @run, drop_event_types: []) do
        @plans = Demo::Catalog.ensure!
        steps
      end
      finish("passed")
    rescue ExpectationFailed => error
      finish("failed", "Expectation failed: #{error.message}")
    rescue StandardError => error
      finish("failed", "#{error.class}: #{error.message}")
    end

    private

    def steps
      raise NotImplementedError
    end

    def finish(status, error = nil)
      @run.update!(status: status, error: error, log: @log, finished_at: BillingClock.now,
        customer_id: @customer&.id, subscription_id: @subscription&.id)
      @run
    end

    def log(step, detail = nil)
      @log << { step: step, detail: detail, at: BillingClock.now.iso8601 }.compact
    end

    # --- steps -----------------------------------------------------------------------------

    def customer(card: "pm_card_visa", exp: [ 12, 2030 ])
      @customer = Customers::Create.call(name: "#{self.class.title} ##{@run.id}", email: "lab-#{@run.id}@scenarios.test")
      log("Customer created", @customer.name)
      card(card, exp: exp) if card
      @customer
    end

    def card(token, exp: [ 12, 2030 ])
      PaymentMethods::Attach.call(@customer.reload, token: token, exp_month: exp[0], exp_year: exp[1], make_default: true)
      log("Default card set", "#{token} (expires #{exp[0]}/#{exp[1]})")
    end

    def subscribe(plan_code)
      @subscription = Subscriptions::Create.call(customer: @customer.reload, plan: @plans.fetch(plan_code))
      log("Subscribed", "#{@plans.fetch(plan_code).name}: #{subscription.status}")
    end

    def subscription
      @subscription.reload
    end

    def advance_days(days)
      remaining = days
      while remaining.positive?
        chunk = [ remaining, BillingClock::MAX_ADVANCE_DAYS ].min
        BillingClock.advance!(days: chunk)
        remaining -= chunk
      end
      log("Clock advanced #{days} day#{'s' unless days == 1}", "subscription is #{subscription.status}")
    end

    def advance_to_period_end
      advance_days(((subscription.current_period_end - BillingClock.now) / 1.day).ceil)
    end

    # The provider will emit the next event of this type as dropped: it never reaches the
    # engine unless delivered by hand.
    def drop_next(event_type)
      Current.drop_event_types = (Current.drop_event_types || []) + [ event_type ]
      log("Provider will lose the next #{event_type}")
    end

    def deliver_dropped(event_type)
      event = outbox.where(event_type: event_type, delivery_status: "dropped").last
      FakeStripe::Dispatcher.redeliver(event)
      log("Lost #{event_type} delivered late", "inbox: #{event.reload.last_delivery_result}")
    end

    def redeliver(event_type, times:)
      event = outbox.where(event_type: event_type, delivery_status: "delivered").last
      times.times { FakeStripe::Dispatcher.redeliver(event) }
      log("#{event_type} delivered #{times} more time#{'s' unless times == 1}")
    end

    def change_plan(plan_code)
      target = subscription
      plan = @plans.fetch(plan_code)
      quote = PlanChanges::Quote.new(subscription: target, to_plan: plan, strategy: "immediate")
      change = PlanChanges::Apply.call(target, lock_version: target.lock_version, to_plan: plan, strategy: "immediate",
        proration_date: quote.proration_date)
      log("Plan changed to #{plan.name}", "#{change.kind}, net #{change.net_cents} cents")
      quote
    end

    def refund(amount_cents, destination:)
      invoice = subscription.invoices.paid.order(:id).first
      Refunds::Create.call(invoice, amount_cents: amount_cents, destination: destination, reason: "service_issue")
      log("Refunded #{amount_cents} cents to #{destination.humanize(capitalize: false)}")
    end

    def retry_payment
      invoice = subscription.invoices.open.order(:id).last
      Invoices::RequestPayment.call(invoice)
      log("Payment retried", "#{invoice.number}: #{invoice.reload.status}")
    end

    def reconcile
      run = Reconciliation::Run.call(triggered_by: "admin", subscription: subscription)
      log("Reconciliation ran", "#{run.discrepancies_found} difference#{'s' unless run.discrepancies_found == 1} found")
      run
    end

    def expect_that(description)
      raise ExpectationFailed, description unless yield

      log("✓ #{description}")
    end

    # The domain must refuse this; the scenario checks the refusal itself.
    def expect_refused(description, code)
      yield
      raise ExpectationFailed, "#{description} (it was accepted)"
    rescue DomainError => error
      raise ExpectationFailed, "#{description} (refused with #{error.code}, expected #{code})" unless error.code == code

      log("✓ #{description}", "refused: #{error.code}")
    end

    # The clock is shared: while a scenario advances days, other subscriptions renew too and
    # their events are emitted during the run. Only this scenario's subscription counts.
    def outbox
      FakeStripe::MockedWebhookEvent.where(scenario_run_id: @run.id, provider_subscription_id: @subscription&.provider_subscription_id)
        .order(:id)
    end

    def inbox_row(event_type)
      WebhookEvent.find_by(provider_event_id: outbox.where(event_type: event_type).last&.event_id)
    end
  end
end
