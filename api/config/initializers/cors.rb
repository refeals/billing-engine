# The Vue app (web/) is served on its own origin (Vite locally, its own domain in the
# deploy), so the browser needs CORS to call this API. `credentials: true` lets it send the
# session cookie; that requires the explicit origin below, never "*".
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins ENV.fetch("WEB_ORIGIN", "http://localhost:3000")

    resource "*",
      headers: :any,
      methods: [ :get, :post, :put, :patch, :delete, :options, :head ],
      credentials: true
  end
end
