# Billing Engine

A subscription billing engine for a fictional SaaS that sells subscriptions to gyms and
fitness studios. It is a portfolio project focused on one narrow, easy-to-get-wrong problem:
**managing the financial lifecycle of a subscription correctly**.

It covers what usually goes wrong in real billing systems: a strict subscription state
machine, idempotent webhook processing, mid-cycle proration, a dunning schedule for failed
payments, reconciliation against the payment provider, and an append-only audit trail.

The payment provider (Stripe) is simulated in-process. No real network calls are made, and a
simulated clock lets you fast-forward weeks of billing in seconds.

> **Status:** in progress. The foundation is done; features ship one plan at a time (see
> [Roadmap](#roadmap)).

## Stack

| Part | Technology |
|---|---|
| API | Ruby 3.4, Rails 8.1 (API-only), SQLite, RSpec |
| Web | Vue 3 (Composition API), TypeScript, Pinia, Vue Router, Tailwind CSS v4, Vitest |
| CI | GitHub Actions (lint, security scans, tests, build) |

## Quick start

### Requirements

- Ruby 3.4.11 (see `api/.ruby-version`)
- `sqlite3` command-line tool (Rails uses it to load `db/structure.sql`)
- Node.js 22.18+ or 24.12+
- pnpm 10

### Setup and run

```sh
bin/setup   # installs gems and packages, prepares the SQLite database
bin/dev     # starts the API and the web app together
```

| App | URL |
|---|---|
| Web | http://localhost:3000 |
| API | http://localhost:3001/api/v1 |

### Environment variables

All optional; the defaults work for local development.

| Variable | App | Default | Purpose |
|---|---|---|---|
| `VITE_API_URL` | web | `http://localhost:3001/api/v1` | API base URL |
| `WEB_ORIGIN` | api | `http://localhost:3000` | Origin allowed by CORS |
| `SIMULATOR_ENABLED` | api | `true` in development/test | Mounts the simulator endpoints (clock, fake provider) |
| `PORT` | api | `3001` | API port |

### Tests

```sh
cd api && bundle exec rspec
cd web && pnpm test:unit
```

## Architecture decisions

- **Simulated clock.** Billing flows span weeks (trials, renewals, a 14-day dunning
  schedule), so every piece of code reads time from `BillingClock.now`, never from
  `Time.current`. A custom RuboCop cop (`Billing/DirectTimeAccess`) fails the build if real
  time is read anywhere else. Advancing the clock runs one tick per simulated day, so work due
  on day 3 happens on day 3 even when you jump a week. Time only moves forward, except for an
  explicit reset.
- **Append-only audit trail, enforced by the database.** Every state change writes a row
  to `billing_events` through a single entry point (`Audit.record`), inside the same
  transaction as the change itself, so both commit or neither does. Rows can't be changed
  afterwards: the model refuses updates and deletes, and SQLite triggers refuse them too, so
  paths that skip the model (`update_all`, `delete_all`, raw SQL) fail as well. Each event
  stores both business time (`occurred_at`, from the simulated clock) and the real time it
  was written.
- **`structure.sql` instead of `schema.rb`.** `schema.rb` can't represent triggers, so a test
  or freshly created database would silently lose the append-only guarantee. The cost is
  needing the `sqlite3` CLI.
- **Money as integer cents.** Every amount is stored as `*_cents` integers with a `currency`
  column (always `USD`). Floats never touch money.
- **One error shape, one list shape.** Every API error is
  `{ "error": { "code", "message", "details" } }`, with 422 for business-rule violations, 409
  for concurrent-edit conflicts and 404 for missing records. Every list is
  `{ "data": [...], "meta": { "page", "per_page", "total_count", "total_pages" } }`.
- **No authentication.** The app models a single back-office operator. Authentication is out
  of scope for a project about billing correctness.
- **Lean Rails.** Only the frameworks in use are loaded (Active Record, Active Job, Action
  Controller). Deployment tooling was removed, since the project is meant to run locally.

## Edge cases handled

- The simulated clock can't move backwards (except through an explicit reset), and advancing
  several days runs each day's work in order.
- A tick that fails rolls back that simulated day instead of leaving time advanced with
  half-done work.
- Updating or deleting an audit row is refused by the database, even through raw SQL.
- A business change and its audit row can't be split: recording an audit event outside a
  transaction raises, and rolling back the change rolls back the event.

## Roadmap

Each feature is planned in [`docs/`](docs/) before it is built. The brief and every
agreed decision live in [`docs/00-prompt.md`](docs/00-prompt.md).

| # | Feature | Status |
|---|---|---|
| 01 | [Foundation](docs/01-foundation.md) | Done |
| 02 | [Audit log](docs/02-audit-log.md) | Done |
| 03 | [Catalog and customers](docs/03-catalog-and-customers.md) | Planned |
| 04 | [Subscription state machine](docs/04-subscription-state-machine.md) | Planned |
| 05 | [Webhook ingestion and idempotency](docs/05-webhook-ingestion.md) | Planned |
| 06 | [Fake payment provider](docs/06-fake-payment-provider.md) | Planned |
| 07 | [Invoicing and payments](docs/07-invoicing-and-payments.md) | Planned |
| 08 | [Plan changes and proration](docs/08-plan-changes-and-proration.md) | Planned |
| 09 | [Refunds](docs/09-refunds.md) | Planned |
| 10 | [Dunning](docs/10-dunning.md) | Planned |
| 11 | [Reconciliation](docs/11-reconciliation.md) | Planned |
| 12 | [Scenario Lab and seeds](docs/12-scenario-lab-and-seeds.md) | Planned |
| 13 | [Dashboard](docs/13-dashboard.md) | Planned |
| 14 | [Documentation and release](docs/14-documentation-and-release.md) | Planned |

## Project structure

```
api/    Rails API: app/services (business logic), app/serializers, app/errors, spec/
web/    Vue app: src/api (HTTP client), src/features (screens per domain), src/stores
docs/   Brief, decisions and one plan per feature
bin/    setup and dev scripts for both apps
```
