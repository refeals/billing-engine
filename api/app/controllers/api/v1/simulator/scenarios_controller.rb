module Api
  module V1
    module Simulator
      class ScenariosController < BaseController
        include Pagination

        def index
          render json: { data: Scenarios::Catalog.all.map { |scenario| { key: scenario.key, title: scenario.title, description: scenario.description } } }
        end

        # Synchronous: a scenario advances the simulated clock a few weeks at most, and the
        # operator wants to see the outcome right away. A failed check is a normal response
        # (status "failed"), not an error.
        def run
          scenario = Scenarios::Catalog.fetch(params[:id])
          render json: ScenarioRunSerializer.new(scenario.call), status: :created
        end

        def runs
          scenario_runs, meta = paginate(ScenarioRun.newest_first)
          render json: { data: scenario_runs.map { |scenario_run| ScenarioRunSerializer.new(scenario_run) }, meta: meta }
        end
      end
    end
  end
end
