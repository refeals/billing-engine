# 16 — Demo login

## Goal

Put the back-office behind a simple, working email-and-password login with a single demo
user whose credentials are printed on the login screen. Every existing screen moves inside
the signed-in area; a "Sign out" button ends the session and returns to the login screen.

The point is not to keep visitors out (the credentials are public) but to show a real
authentication flow done properly: hashed password, server-side sessions in an HttpOnly
cookie, every API endpoint protected, and the frontend redirecting to the login screen when
a session is missing or expired.

## Depends on

- `15-deploy-with-dokploy.md` (the live demo runs on two subdomains of the same site).

## Scope

**In**
- `users` and `sessions` tables, one seeded demo user.
- Session endpoints: sign in, current session, sign out.
- Authentication required on every `/api/v1` endpoint except the provider's webhook and the
  session endpoints.
- Login screen, route guard, sign-out button, redirect on 401.

**Out**
- Sign-up, password reset, email confirmation, roles, multiple operators, "remember me",
  OAuth. The demo user is the only user.

## Decisions

1. **Server-side sessions in an HttpOnly cookie, not a token in `localStorage`.** Same shape
   as Rails 8's authentication generator: a `sessions` row per sign-in, and a signed,
   HttpOnly cookie holding its id. JavaScript never sees a credential, so an XSS bug can't
   steal one, and signing out deletes the row, which really ends the session on the server
   (a JWT can't be revoked that way).
2. **Why the cookie works across the two domains.** `billing.rafaelsiqueira.dev` and
   `billing-api.rafaelsiqueira.dev` are different origins but the **same site**
   (`rafaelsiqueira.dev`); locally, `localhost:3000` and `localhost:3001` are too (ports don't
   count for "site"). So a `SameSite=Lax` cookie set by the API is sent on the web app's
   `fetch` calls, as long as the request uses `credentials: "include"` and CORS answers with
   `Access-Control-Allow-Credentials: true` for that exact origin (already an explicit
   origin, never `*`). The cookie is host-only (set by the API host, no `Domain`), `Secure`
   in production and expires after 7 days.
3. **CSRF.** Browsers only attach a `SameSite=Lax` cookie to cross-site *navigations*, never
   to cross-site `fetch`/form POSTs, so another site can't act with the session. Every
   state-changing request is JSON, which forces a CORS preflight that only the web origin
   passes. No CSRF token is needed.
4. **The demo user comes from code, not from the seeds alone.** Credentials are constants
   (`Demo::User::EMAIL = "demo@billing-engine.dev"`, `PASSWORD = "demo-billing-2026"`), shown
   on the login screen. `Demo::User.ensure!` creates the user if missing and resets the
   password if it changed; it runs from the seeds and from the Docker entrypoint after
   `db:prepare`, so an existing production database gets the user on the next deploy
   without a reseed.
5. **The demo reset keeps users and sessions.** `Demo::Reset` wipes billing data; the demo
   user and the people currently signed in are not billing data. `users` and `sessions` are
   added to the tables it skips, so the nightly reset doesn't sign everyone out.
6. **What stays public.** `POST /api/v1/webhooks/stripe` (the provider has no session; it
   has its own guard, signature verification), `GET /up`, and the session endpoints. The
   fake provider delivers in-process through `Webhooks::Ingest`, so it is unaffected.
7. **Actor attribution is unchanged.** Requests stay attributed to `admin` in the audit log;
   with one user there is nothing more to say. Sign-in and sign-out aren't audited: they
   aren't billing events.
8. **Brute force.** Rails 8's `rate_limit` on sign-in (10 attempts per 3 minutes per
   visitor), with its own in-process store (see implementation decisions).

## Backend (`api/`)

### Schema

- `users`: `email` (unique, normalized: stripped, downcased), `password_digest`, `name`,
  timestamps.
- `sessions`: `user_id` (FK), `ip_address`, `user_agent`, `last_seen_at`, timestamps.
  Expired rows (older than 7 days) are deleted at sign-in, keeping the table small without
  a job.

### Code

- Gem `bcrypt` (for `has_secure_password`).
- `app/models/user.rb`: `has_secure_password`, `normalizes :email`, `has_many :sessions`.
- `app/models/session.rb`: `belongs_to :user`, `scope :expired`, `EXPIRES_IN = 7.days`.
- `app/controllers/concerns/authentication.rb`, included in `Api::V1::BaseController`:
  - `before_action :require_authentication` — reads the signed `session_id` cookie, finds
    an unexpired session, sets `Current.session` / `Current.user`, touches
    `last_seen_at` at most once a minute; otherwise answers 401
    `{ "error": { "code": "unauthenticated", ... } }` in the usual error shape.
  - `allow_unauthenticated_access` class method for the session controller.
  - `start_new_session_for(user)` / `terminate_session`.
- API-only apps have no cookie middleware: add `config.middleware.use
  ActionDispatch::Cookies` and `include ActionController::Cookies` in the base controller.
  Cookie options: `httponly: true, same_site: :lax, secure: Rails.env.production?,
  expires: Session::EXPIRES_IN`.
- `app/controllers/api/v1/sessions_controller.rb` (`resource :session`):
  - `POST /api/v1/session` `{ email, password }` → `User.authenticate_by` (constant time
    whether the email exists or not) → 201 `{ "user": { "id", "email", "name" } }`, or 401
    `invalid_credentials` with one message for both wrong email and wrong password;
    `rate_limit to: 10, within: 3.minutes, only: :create` → 429 `too_many_attempts`.
  - `GET /api/v1/session` → 200 with the user, or 401 (how the web app learns whether it
    is signed in on page load).
  - `DELETE /api/v1/session` → deletes the row and the cookie, 204.
- `Current`: `attribute :session`, `delegate :user`.
- `config/initializers/cors.rb`: `credentials: true`.
- `app/services/demo/user.rb`: `EMAIL`, `PASSWORD`, `ensure!`; called by `Demo::Seed` and
  by `lib/tasks/demo.rake` (`bin/rails demo:ensure_user`), which `bin/docker-entrypoint`
  runs after `db:prepare`.
- `Demo::Reset`: skip `users` and `sessions`.

### Specs

- Request: sign in (cookie set, HttpOnly, SameSite=Lax), wrong password and unknown email
  get the same 401, rate limit returns 429, current session, sign out (row gone, cookie
  cleared, next request 401), expired session → 401.
- Every protected endpoint answers 401 without a session: one spec iterates over
  `Rails.application.routes` under `/api/v1`, skipping the public ones, so a new controller
  can't be left open by accident.
- Webhook endpoint still works without a session.
- `Demo::User.ensure!` is idempotent and restores a changed password; `Demo::Reset` keeps
  users and sessions.
- Existing request specs: `spec/support/authentication.rb` signs the demo user in before
  every `type: :request` example (opt out with `:unauthenticated`), so they don't change.

## Frontend (`web/`)

- `src/api/client.ts`: `credentials: 'include'` on every request. A 401 on anything but the
  session endpoints calls an `onUnauthenticated` hook (set by the auth store), so an
  expired session anywhere lands on the login screen instead of a broken view.
- `src/api/session.ts`: `fetchSession`, `signIn`, `signOut`, `DEMO_CREDENTIALS` (the same
  values as `Demo::User`; a comment points at the Ruby constants).
- `src/stores/auth.ts` (Pinia): `user`, `status` (`unknown | signed_in | signed_out`),
  `load()` (once, on first navigation), `signIn()`, `signOut()`.
- Router:
  - `/login` → `LoginView`, `meta: { public: true, layout: 'blank' }`; everything else is
    private.
  - `beforeEach`: load the session once; private route while signed out →
    `/login?redirect=<path>`; `/login` while signed in → dashboard.
  - After sign-in: go to `redirect` if it is an internal path (starts with `/`, not `//`),
    else the dashboard. Prevents an open redirect.
- `App.vue`: renders `AppLayout` for private routes and a bare `RouterView` for `/login`, so
  the sidebar, clock and their API calls never run while signed out.
- `src/features/auth/LoginView.vue`: centered card with the product name, email and
  password fields, "Sign in" button, error message (`invalid_credentials`,
  `too_many_attempts`), and a "Demo credentials" box showing both values with a "Use demo
  credentials" button that fills the form.
- Sign out: the signed-in email and a "Sign out" button at the bottom of the sidebar;
  calls `DELETE /session`, resets the auth store, then `router.replace('/login')`. If the
  request fails (already expired), it still goes to the login screen.
- Tests: client sends `credentials: 'include'` and calls the 401 hook; redirect sanitizer
  (`/invoices` ok, `//evil.com` and `https://…` rejected); auth store transitions.

## Deploy

- No new environment variable. The migration and `demo:ensure_user` run in the entrypoint on
  the next deploy; the existing demo data is kept.
- Cloudflare in front of both domains doesn't change cookies (same site, HTTPS end to end).

## Documentation

- README: "Live demo" line gains the demo credentials; architecture decisions: replace
  "No authentication" with the session design (decisions 1–3); edge cases: expired session
  redirects to login, webhook stays public, every endpoint checked by one spec, rate limit;
  Try it: "sign in with the demo credentials shown on the login screen".
- `docs/15`: the "No authentication" risk becomes "public demo credentials".
- `docs/00` §9: session endpoints; §10: `users`, `sessions`.

## Verification

1. `rspec` (new and existing), `rubocop`, `brakeman`; web `lint`, `type-check`, `test:unit`,
   `build-only`.
2. Local, browser: open `/subscriptions` signed out → login with `?redirect=/subscriptions`;
   sign in → lands there; reload → still signed in; sign out → login; back button doesn't
   show data; delete the session row by hand → next click lands on login.
3. Local Docker run as in docs/15, then on the live domains: the cookie is set by
   `billing-api.rafaelsiqueira.dev` and sent from `billing.rafaelsiqueira.dev`
   (`Secure`, `HttpOnly`, `SameSite=Lax`); `curl` without cookie → 401 on
   `/api/v1/dashboard/summary`, 200 on `/up`.

## Decisions taken during implementation

- **The rate limit has its own store** (`SessionsController::SIGN_IN_ATTEMPTS`, an in-process
  `MemoryStore`) instead of `Rails.cache`, which is a null store in tests (the limit would
  be untestable) and unset in production. One process, one store; no production.rb change.
- **Rate limited per real visitor.** Behind Cloudflare, `request.remote_ip` is the Cloudflare
  edge, shared by many visitors, so one person hammering the form would lock out everyone
  behind that edge. The limit (and `sessions.ip_address`) use `CF-Connecting-IP` when
  present. Forging it when calling the VPS directly only buys a fresh allowance for a
  password that is public anyway.
- **The reset keeps accounts only when it reseeds**; the bare wipe used by the seed spec's
  cleanup deletes users and sessions too, so the test database is left empty.
- **Session expiry uses real time** (`Session.wall_clock_now`, the one sanctioned exception
  to the `Billing/DirectTimeAccess` cop): advancing the simulated clock a month must not sign
  the operator out.
- **The app mounts after the first navigation settles** (`router.isReady()`), so a signed-out
  visitor never sees the back-office shell flash, and the sidebar and clock (which call the
  API) never render without a session.
- **The sidebar sticks to the viewport height** on desktop, so "Sign out" stays visible at
  its foot instead of below a long page.
- Request specs sign in as the demo user by default (`spec/support/authentication.rb`) and
  clear the rate-limit store per example; the anonymous controller in `base_controller_spec`
  opts out, since it tests error rendering.
- Verified in a real browser (Chrome driven through the DevTools protocol): a private URL
  redirects to `/login?redirect=…`, "Use demo credentials" + Sign in returns to it, a reload
  keeps the session, "Sign out" lands on the login, and private URLs redirect again.
  The Docker image wasn't rebuilt (Docker daemon not running); the only entrypoint change is
  `bin/rails demo:ensure_user` after `db:prepare`.

## Acceptance criteria

- Signed out, no screen or API data is reachable; the login screen shows the demo
  credentials and signing in with them opens the dashboard.
- "Sign out" returns to the login screen and the old cookie no longer works.
- The nightly demo reset doesn't sign anyone out.
