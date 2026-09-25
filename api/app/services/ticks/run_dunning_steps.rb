module Ticks
  # Runs the dunning steps that fall due today, one per case.
  class RunDunningSteps
    def self.call(at:)
      executed = 0
      canceled = 0

      DunningCase.open.where(next_step_at: ..at).includes(:invoice, subscription: :customer).find_each do |dunning_case|
        # Paid or corrected by another path (e.g. a reconciliation correction): the schedule no
        # longer applies, and its steps (a past_due-only cancellation) would fail.
        unless dunning_case.subscription.status == "past_due"
          ::Dunning::CloseStale.call(dunning_case)
          next
        end

        step = dunning_case.next_step
        next unless ::Dunning::RunStep.call(dunning_case, step, at: at)

        executed += 1
        canceled += 1 if step == "day_14_cancel"
      end

      { dunning_steps_executed: executed, subscriptions_canceled_by_dunning: canceled }
    end
  end
end
