class ScenarioRun < ApplicationRecord
  belongs_to :customer, optional: true
  belongs_to :subscription, optional: true

  enum :status, %w[running passed failed].index_by(&:itself), validate: true

  scope :newest_first, -> { order(id: :desc) }

  def scenario
    Scenarios::Catalog.fetch(scenario_key)
  end
end
