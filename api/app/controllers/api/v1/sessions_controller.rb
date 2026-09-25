module Api
  module V1
    class SessionsController < BaseController
      allow_unauthenticated_access only: %i[show create]

      # Per process, like the rest of the deploy (one Puma process). Explicit instead of
      # Rails.cache, which is a null store in tests and unset in production.
      SIGN_IN_ATTEMPTS = ActiveSupport::Cache::MemoryStore.new

      # Per visitor, not per Cloudflare edge: otherwise one person hammering the form would
      # lock everyone behind the same edge out of the demo.
      rate_limit to: 10, within: 3.minutes, only: :create, store: SIGN_IN_ATTEMPTS, by: -> { client_ip }, with: -> {
        render_error(:too_many_requests, "too_many_attempts", "Too many sign-in attempts. Try again in a few minutes.")
      }

      def show
        session = resume_session
        return render_error(:unauthorized, "unauthenticated", "Not signed in") unless session

        render json: serialize(session.user)
      end

      # One message for an unknown email and a wrong password, and authenticate_by takes the
      # same time for both, so the endpoint doesn't reveal which emails exist.
      def create
        user = User.authenticate_by(email: params[:email].to_s, password: params[:password].to_s)
        return render_error(:unauthorized, "invalid_credentials", "Wrong email or password") unless user

        start_new_session_for(user)
        render json: serialize(user), status: :created
      end

      def destroy
        terminate_session
        head :no_content
      end

      private

      def serialize(user)
        { user: user.slice(:id, :email, :name) }
      end
    end
  end
end
