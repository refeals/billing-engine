class DunningStep < ApplicationRecord
  include AppendOnly

  belongs_to :dunning_case

  validates :step, inclusion: { in: ->(_) { Dunning::Schedule::STEPS.keys } }
  validates :scheduled_at, :executed_at, :outcome, presence: true
end
