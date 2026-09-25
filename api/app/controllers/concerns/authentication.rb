# Every API endpoint requires a signed-in session unless its controller opts out. The browser
# holds only a signed, HttpOnly cookie with the session row's id: JavaScript never sees a
# credential, and deleting the row ends the session for real.
module Authentication
  extend ActiveSupport::Concern

  COOKIE = :session_id

  included do
    before_action :require_authentication
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private

  def require_authentication
    session = resume_session
    raise DomainError.new("Sign in to continue", code: "unauthenticated", http_status: :unauthorized) unless session

    session.touch_last_seen
  end

  def resume_session
    Current.session ||= find_session_by_cookie
  end

  def find_session_by_cookie
    id = cookies.signed[COOKIE]
    session = id && Session.find_by(id: id)
    return session if session && !session.expired?

    cookies.delete(COOKIE) if id
    nil
  end

  def start_new_session_for(user)
    user.sessions.expired.delete_all
    session = user.sessions.create!(ip_address: client_ip, user_agent: request.user_agent&.first(255),
      last_seen_at: Session.wall_clock_now)
    # SameSite=Lax: the web app (billing.…) and the API (billing-api.…) are the same site, so
    # the cookie goes with its fetch calls, but never with another site's requests.
    cookies.signed[COOKIE] = {
      value: session.id, httponly: true, same_site: :lax, secure: Rails.env.production?,
      expires: Session::EXPIRES_IN
    }
    Current.session = session
  end

  # Behind Cloudflare, request.remote_ip is the Cloudflare edge (its ranges aren't trusted
  # proxies), which many visitors share; the visitor's own address comes in CF-Connecting-IP.
  # A client could forge that header when calling the VPS directly, but that only buys it a
  # fresh sign-in allowance for a password that is public anyway.
  def client_ip
    request.headers["CF-Connecting-IP"].presence || request.remote_ip
  end

  def terminate_session
    Current.session&.destroy
    Current.session = nil
    cookies.delete(COOKIE)
  end
end
