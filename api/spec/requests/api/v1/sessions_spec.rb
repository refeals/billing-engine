require "rails_helper"

RSpec.describe "Sessions", :unauthenticated, type: :request do
  let(:credentials) { { email: Demo::User::EMAIL, password: Demo::User::PASSWORD } }

  before { Demo::User.ensure! }

  def json
    response.parsed_body
  end

  it "signs in with a cookie JavaScript can't read and other sites can't send" do
    post "/api/v1/session", params: credentials, as: :json

    expect(response).to have_http_status(:created)
    expect(json["user"]).to include("email" => Demo::User::EMAIL)
    cookie = response.headers["Set-Cookie"].to_s
    expect(cookie).to match(/session_id=/).and match(/httponly/i).and match(/samesite=lax/i)
  end

  it "accepts the email in any case and with surrounding spaces" do
    post "/api/v1/session", params: credentials.merge(email: "  DEMO@billing-engine.dev "), as: :json

    expect(response).to have_http_status(:created)
  end

  it "answers the same for an unknown email and a wrong password" do
    post "/api/v1/session", params: credentials.merge(password: "wrong"), as: :json
    wrong_password = [ response.status, json["error"] ]

    post "/api/v1/session", params: credentials.merge(email: "nobody@example.test"), as: :json

    expect([ response.status, json["error"] ]).to eq(wrong_password)
    expect(wrong_password.first).to eq(401)
    expect(wrong_password.last["code"]).to eq("invalid_credentials")
  end

  it "slows down guessing: the eleventh attempt within three minutes is refused" do
    10.times { post "/api/v1/session", params: credentials.merge(password: "wrong"), as: :json }

    post "/api/v1/session", params: credentials, as: :json

    expect(response).to have_http_status(:too_many_requests)
    expect(json.dig("error", "code")).to eq("too_many_attempts")
  end

  it "limits each visitor on its own behind Cloudflare, not everyone sharing an edge" do
    10.times do
      post "/api/v1/session", params: credentials.merge(password: "wrong"), as: :json,
        headers: { "CF-Connecting-IP" => "203.0.113.7" }
    end

    post "/api/v1/session", params: credentials, as: :json, headers: { "CF-Connecting-IP" => "198.51.100.9" }

    expect(response).to have_http_status(:created)
  end

  it "reports the current session, and 401 without one" do
    get "/api/v1/session"
    expect(response).to have_http_status(:unauthorized)

    post "/api/v1/session", params: credentials, as: :json
    get "/api/v1/session"

    expect(response).to have_http_status(:ok)
    expect(json["user"]).to include("name" => Demo::User::NAME)
  end

  it "signs out on the server: the old cookie no longer works" do
    post "/api/v1/session", params: credentials, as: :json
    old_cookie = cookies[:session_id]

    delete "/api/v1/session"
    expect(response).to have_http_status(:no_content)
    expect(Session.count).to eq(0)

    cookies[:session_id] = old_cookie
    get "/api/v1/dashboard/summary"
    expect(response).to have_http_status(:unauthorized)
  end

  it "refuses an expired session" do
    post "/api/v1/session", params: credentials, as: :json
    Session.update_all(created_at: 8.days.ago)

    get "/api/v1/dashboard/summary"

    expect(response).to have_http_status(:unauthorized)
    expect(json.dig("error", "code")).to eq("unauthenticated")
  end

  it "keeps the provider's webhook endpoint open: the provider has no session" do
    post "/api/v1/webhooks/stripe", params: Rails.root.join("spec/fixtures/webhooks/invoice_finalized.json").read,
      headers: { "Content-Type" => "application/json" }

    expect(response).to have_http_status(:ok)
  end
end
