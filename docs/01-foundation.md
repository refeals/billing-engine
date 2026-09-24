# 01 — Foundation

## Goal

Get both apps into a shape where every later feature plugs in without rework: API
conventions, error handling, the simulated clock, the frontend shell and CI.

## Depends on

- `00-prompt.md`

## Scope

**In**
- Rails API conventions (`/api/v1` namespace, error rendering, CORS, JSON only).
- `BillingClock` and the `simulation_clock` table.
- Tick pipeline skeleton (later plans register steps on it).
- Clock endpoints under `/api/v1/simulator/clock`.
- Vue shell: layout, sidebar, router, API client, header clock widget.
- Test setup for both apps, lint, CI.
- README skeleton.

**Out**
- Any domain table other than `simulation_clock`.

## Backend

### Conventions
- Everything under `Api::V1` controllers; routes in `namespace :api { namespace :v1 }`.
- Business logic lives in plain Ruby service objects under `app/services/<domain>/`, named as
  verbs (`Subscriptions::Cancel`). Controllers only parse params, call one service and render.
- Serialization with plain serializer classes under `app/serializers/` (no extra gem).
- Remove unused Rails 8 defaults that add noise to a public repo (Kamal, Thruster, Solid Cable,
  image_processing) unless a later plan needs them. Keep Solid Queue as the Active Job adapter
  (decision 4 in `00-prompt.md`).
- Add `rack-cors`, allowing the Vite dev origin (`http://localhost:3000`).
- Rails API port: `3001`.

### Error handling
- `ApplicationController` rescues a small hierarchy of domain errors and renders the
  standard shape from `00-prompt.md` §9:
  - `DomainError` (base) → 422
  - `InvalidTransitionError < DomainError` → 422 `invalid_transition`
  - `StaleObjectError` (from `ActiveRecord::StaleObjectError`) → 409 `stale_object`
  - `ActiveRecord::RecordNotFound` → 404 `not_found`
  - `ActiveRecord::RecordInvalid` → 422 `validation_failed`, with field errors in `details`

### Simulated clock
- Table `simulation_clock`: `id`, `current_time`, `updated_at`. Single row, enforced by a
  check constraint on `id = 1`.
- `BillingClock.now` returns `simulation_clock.current_time`. If the row doesn't exist it's
  created with the real current time.
- `BillingClock.advance!(days:)` moves time forward, then runs `Ticks::Run`.
- `BillingClock.reset!` sets the clock back to real time.
- Time can only move forward, except through reset. Going back would break the ordering
  every later feature relies on.
- A RuboCop custom cop (or a simple CI grep) forbids `Time.current`, `Time.now` and
  `Date.today` outside `BillingClock`. It's cheap and it's the kind of guard that makes the
  rule stick.

### Tick pipeline
- `Ticks::Run` executes registered steps in a fixed order, one day at a time. Advancing
  7 days runs 7 ticks, so a dunning step due on day 3 fires on day 3 and not on day 7.
- Each step returns counters that go into the `tick_report`.
- This plan ships the pipeline with no steps.

### Endpoints
- `GET /api/v1/simulator/clock`
- `POST /api/v1/simulator/clock/advance` — `{ "days": 1..30 }`
- `POST /api/v1/simulator/clock/reset`
- `GET /up` (Rails default health check, kept).

Simulator routes are mounted only when `SIMULATOR_ENABLED=true`, default on in development.

## Frontend

- Folder layout under `web/src/`:
  - `api/` — typed HTTP client (thin `fetch` wrapper) plus one module per resource.
  - `components/` — shared UI (status badge, money, date, empty state, JSON viewer).
  - `features/<domain>/` — views and components per domain.
  - `stores/` — Pinia, only for global state (the clock).
  - `router/`
- API client: base URL from `VITE_API_URL`, parses the standard error shape into a typed
  `ApiError`, surfaces 409 as "someone else changed this, reload".
- Layout: sidebar with every section from `00-prompt.md` §8 (disabled until its plan ships),
  header with the clock widget (current simulated date, +1d / +3d / +7d, reset).
- Clock store: after an advance, the current view refetches its data.
- Formatting helpers: `formatMoney(cents)` in USD, dates always shown in simulated time.

## Tests

- Backend (RSpec): `BillingClock` (advance, reset, never backwards, one tick per day), error
  rendering for each error class, clock endpoints.
- Frontend: Vitest set up; API client error parsing; money formatting.

## CI

GitHub Actions workflow with two jobs:
- `api`: bundle install, `rubocop`, `brakeman`, tests.
- `web`: pnpm install, lint, type-check, tests, build.

## Documentation

- README skeleton: problem statement, stack, how to run locally (both apps, env vars,
  ports), links to `docs/`.
- README section "Architecture decisions" started with: simulated clock, money in cents,
  no authentication.

## Acceptance criteria

- `bin/dev` (or two documented commands) starts both apps; the web app shows the layout and
  the clock.
- Advancing the clock in the UI changes the date shown and returns a `tick_report`.
- CI is green on both jobs.
- No direct `Time.current` usage outside `BillingClock`.

## Resolved decisions

1. **Backend tests:** RSpec + FactoryBot. Remove the default `test/` folder.
2. **Styling:** Tailwind CSS v4 with a small set of design tokens (colors per subscription
   status, spacing, typography) defined once in the theme.
3. **UI copy:** English; amounts formatted as USD.
