require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "action_controller/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Api
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    # `rubocop` holds custom cops loaded by RuboCop itself, not by the app.
    config.autoload_lib(ignore: %w[assets tasks rubocop])

    config.api_only = true
    config.time_zone = "UTC"

    config.generators do |generate|
      generate.test_framework :rspec
      generate.fixture_replacement :factory_bot, dir: "spec/factories"
    end

    # The simulator (fake provider, clock controls) must never be reachable in a
    # real deployment, so it's opt-in outside development and test.
    config.x.simulator_enabled = ENV.fetch("SIMULATOR_ENABLED") { Rails.env.local?.to_s } == "true"
  end
end
