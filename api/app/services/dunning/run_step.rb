module Dunning
  # Runs one step of a case, at most once. The step row is inserted first, under a unique
  # (case, step) index: if the daily job runs twice, the second insert fails and nothing
  # else happens. If the action fails, the savepoint rolls the step row back with it.
  class RunStep < ApplicationService
    def initialize(dunning_case, step, at:, subscription: nil)
      @dunning_case = dunning_case
      @step = step
      @at = at
      # The caller's instance, when it has one: a second copy would carry a stale
      # lock_version and fail the next save.
      @subscription = subscription || dunning_case.subscription
    end

    # Returns the step row, or nil when this step had already run.
    def call
      ActiveRecord::Base.transaction(requires_new: true) do
        step_row = @dunning_case.steps.create!(step: @step, scheduled_at: Schedule.due_at(@dunning_case, @step),
          executed_at: @at, outcome: Schedule::OUTCOMES.fetch(@step))
        perform(step_row)
        Audit.record(event_type: "dunning.step_executed", subject: @dunning_case,
          context: { step: @step, outcome: step_row.outcome, invoice: @dunning_case.invoice.number })
        step_row
      end
    rescue ActiveRecord::RecordNotUnique
      nil
    end

    private

    def perform(step_row)
      case @step
      when "day_0_notice"
        Notify.call(@dunning_case, "payment_failed", step: step_row)
        schedule_next
      when "day_3_retry"
        Notify.call(@dunning_case, "payment_retry", step: step_row)
        # Only a request: the provider answers by webhook. Paid → the case recovers; failed
        # again → the same case waits for day 7.
        Invoices::RequestPayment.call(@dunning_case.invoice,
          metadata: { dunning_case_id: @dunning_case.id, dunning_step_id: step_row.id })
        schedule_next
      when "day_7_suspend"
        @subscription.update!(access_suspended_at: @at)
        Audit.record(event_type: "subscription.access_suspended", subject: @subscription,
          after: { access_suspended_at: @at.iso8601 })
        Notify.call(@dunning_case, "access_suspended", step: step_row)
        schedule_next
      when "day_14_cancel"
        exhaust(step_row)
      end
    end

    def schedule_next
      next_step = Schedule.after(@step)
      @dunning_case.update!(last_step: @step, next_step: next_step, next_step_at: Schedule.due_at(@dunning_case, next_step))
    end

    # The case is closed before the cancellation, so the cancellation's own cleanup (which
    # closes open cases as "canceled") leaves this one as "exhausted".
    def exhaust(step_row)
      @dunning_case.update!(status: "exhausted", last_step: @step, next_step: nil, next_step_at: nil,
        closed_at: @at, closed_reason: "dunning_exhausted")

      invoice = @dunning_case.invoice
      invoice.update!(status: "uncollectible")
      Audit.record(event_type: "invoice.marked_uncollectible", subject: invoice,
        before: { status: "open" }, after: { status: "uncollectible" }, context: { amount_due_cents: invoice.amount_due_cents })

      Subscriptions::Transition.call(@subscription, to: "canceled", reason: "dunning_exhausted",
        attributes: { canceled_at: @at, cancellation_reason: "dunning_exhausted", cancel_at_period_end: false })
      Notify.call(@dunning_case, "subscription_canceled", step: step_row)
    end
  end
end
