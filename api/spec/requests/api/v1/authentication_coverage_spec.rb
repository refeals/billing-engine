require "rails_helper"

# Walks every API route, so a new controller can't be left open by forgetting to inherit
# from BaseController.
RSpec.describe "Authentication coverage", :unauthenticated, type: :request do
  PUBLIC = [ %r{\A/api/v1/session\z}, %r{\A/api/v1/webhooks/stripe\z} ].freeze

  routes = Rails.application.routes.routes.filter_map do |route|
    path = route.path.spec.to_s.delete_suffix("(.:format)")
    verb = route.verb.to_s
    next unless path.start_with?("/api/v1/") && verb.present?
    next if PUBLIC.any? { |pattern| pattern.match?(path) }

    [ verb, path.gsub(/:\w+/, "1") ]
  end

  it "covers the API" do
    expect(routes.size).to be > 30
  end

  routes.each do |verb, path|
    it "refuses #{verb} #{path} without a session" do
      process verb.downcase.to_sym, path, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
