# Request specs run signed in as the demo user, like the web app after login. Tag an
# example or group `:unauthenticated` to start without a session.
module AuthenticationHelpers
  def sign_in_as_demo_user
    Demo::User.ensure!
    post "/api/v1/session", params: { email: Demo::User::EMAIL, password: Demo::User::PASSWORD }, as: :json
    raise "demo sign-in failed: #{response.status}" unless response.status == 201
  end
end

RSpec.configure do |config|
  config.include AuthenticationHelpers, type: :request
  config.before(:each, type: :request) do |example|
    # Every example signs in; the sign-in rate limit would otherwise trip after ten.
    Api::V1::SessionsController::SIGN_IN_ATTEMPTS.clear
    sign_in_as_demo_user unless example.metadata[:unauthenticated]
  end
end
