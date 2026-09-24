# 00 — Project brief and agreed decisions

This document is the single source of truth for the scope, rules and design decisions
agreed before implementation started. Later documents in `docs/` build on it.

## 1. Context

A portfolio project: a **billing engine for SaaS**, simulating the subscription back-office
of a fictional product (subscription management for gyms / fitness studios).

The goal is to demonstrate senior-level depth on one narrow problem — managing the financial
lifecycle of a subscription correctly — not to build a complete product.

**Audience:** recruiters and potential clients reading the code and running the demo
locally. It is not meant to run in production with real customers. Choices are driven by
clarity and by showing correct reasoning on hard cases, not by operational concerns
(scaling, deployment, security hardening, compliance).

## 2. Stack

- **Frontend:** Vue 3 (Composition API) + TypeScript — `web/`
- **Backend:** Ruby on Rails, API-only mode — `api/`
- **Database:** SQLite
- **Payments:** no real Stripe integration in this phase. The whole payment layer is mocked
  (fixtures/seeds simulating Stripe webhook events such as `invoice.paid`,
  `invoice.payment_failed`, `customer.subscription.updated`). No real network calls.
  Real Stripe integration is a future phase.

## 3. Domain requirements

1. **Subscription state machine:** `trialing → active → past_due → canceled`, plus `paused`.
   Transitions only from valid previous states. Status is never edited freely.
2. **Idempotent webhook processing (mocked):** an event with the same `event_id` is never
   processed twice.
3. **Proration** when changing plans mid-cycle.
4. **Dunning:** failed-payment sequence — notice on day 0, retry on day 3, access suspension
   on day 7, cancellation on day 14.
5. **Reconciliation:** a mechanism (endpoint and/or job) comparing internal state with the
   "expected" state derived from the mocked events, flagging discrepancies.
6. **Audit:** every state change produces an immutable, append-only record — never a
   destructive update. A screen shows this history per subscription.

## 4. Rules

### Code language
All code is in English, no exceptions: comments, variables, functions, classes, file names,
database tables/columns, JSON keys, CSS classes, branch names, commit messages. Applies to
both Vue and Rails. User-facing copy may be in the product language.

### Commits
- English, at most 60 characters.
- No `Co-Authored-By` or any AI attribution line.
- Commit commands are given in chat, ready to copy and paste into the terminal.

### Documentation
The code is public and will be evaluated by recruiters and potential clients.
- `README.md` in English: the problem, architecture decisions and why, how to run locally.
- Mermaid diagram of the subscription state machine inside the README.
- Explicit **"Edge cases handled"** section listing every hard scenario covered
  (duplicate webhook, downgrade with credit, expired card, partial refund, etc).
- Code comments explain **why**, not what. Names should make the what obvious.

### Workflow
Plan first, implement after review. Each phase waits for explicit approval before the next.

## 5. Architectural premises

- **Simulated clock (`BillingClock`).** All code reads time through it, never `Time.current`
  directly. Without it, the 14-day dunning flow can't be demonstrated. An "advance N days"
  action runs renewals, trial endings and dunning steps deterministically.
- **Fake provider separated from our system.** The fake Stripe owns its own event log
  (outbox, source of truth). Our system owns an inbox. Reconciliation compares both. When
  real Stripe arrives, the outbox goes away and the inbox stays unchanged.
- **Money as integer cents** (`*_cents`) plus a `currency` column. Never floats.
- **Status is never edited directly.** There is no `PATCH status`. Every change goes through
  an explicit action (`cancel`, `pause`, …) or a webhook, validated by the state machine.
- **No authentication.** Single back-office operator. Documented in the README as out of scope.

## 6. Resolved decisions

1. **Day-7 suspension is not `paused`.** The subscription stays `past_due` and
   `access_suspended_at` is set. `paused` is reserved for voluntary pauses requested by the
   customer; mixing both would confuse audit and reconciliation.
2. **Outbox / inbox split.** `mocked_webhook_events` is the fake Stripe outbox (source of
   truth for "expected" state). Idempotency lives in `webhook_events` (our inbox), which
   survives the future real Stripe integration unchanged.
3. **Plan changes.** Upgrades are always immediate, with a proration invoice. Downgrades
   default to `immediate`, with the net credit going to the customer credit balance (to
   demonstrate that edge case). `at_period_end` is also supported.
4. **Jobs.** Advancing the clock runs the "tick" synchronously and deterministically.
   Solid Queue is configured only as the Active Job adapter; no separate worker in the demo.
5. **Currency.** USD only. The `currency` column is kept (Stripe-compatible shape) but
   always `USD`.
6. **Audit hash chain.** Not in this phase — listed under future improvements.
7. **Backend tests.** RSpec + FactoryBot.
8. **Styling.** Tailwind CSS v4.
9. **UI copy language.** English, with amounts in USD.

## 7. Future improvements (out of scope for now)

- Real Stripe integration (signature verification, real API calls). Webhook signature
  verification already sits behind an interface that is a no-op today.
- Hash chain on `billing_events` (`previous_hash`, `entry_hash`) so tampering outside the
  application becomes detectable.
- Authentication / multi-operator access.
- Multi-currency.

## 8. Frontend screens (Vue)

**Global layout:** sidebar plus a header widget with the simulated clock (current date,
+1d / +3d / +7d buttons, reset). Always visible, since it drives the demo.

1. **Dashboard** (`/`) — billing health overview.
   - Subscription counts per status, MRR, `past_due` count, open discrepancies, last 10
     billing events.
   - Shortcuts to the Scenario Lab and to running reconciliation.
2. **Subscriptions list** (`/subscriptions`) — find subscriptions.
   - Table: customer, plan, status badge, period end, dunning stage.
   - Status filter, customer/email search, "New subscription" button.
3. **Subscription detail** (`/subscriptions/:id`) — main operation screen for one subscription.
   - Header: status, plan, current period, trial end, `cancel_at_period_end`.
   - Action buttons driven by `allowed_actions` from the API. The frontend never decides
     which transitions are valid.
   - Tabs: Invoices, Plan changes, Dunning, Payment method, Credit balance.
   - Link to the audit timeline.
4. **Subscription audit timeline** (`/subscriptions/:id/history`) — required audit screen.
   - Chronological, immutable timeline mixing state transitions and billing events.
   - Each item: when, source (webhook / admin / job / reconciliation), before/after diff,
     link to the causing webhook, expandable JSON payload.
   - Filter by event type. Read-only, no edit action.
5. **Change plan** (modal on screen 3) — plan change with proration.
   - New plan select, strategy (`immediate` / `at_period_end`).
   - Proration preview before confirming: unused-time credit, remaining-time charge, net
     amount. Negative net goes to the credit balance.
   - Confirm button uses an idempotency key.
6. **Customers list** (`/customers`) — list and create customers.
7. **Customer detail** (`/customers/:id`)
   - Subscriptions and payment methods (test card with simulated behavior, e.g.
     `declines_insufficient_funds`, `expired`).
   - Append-only credit ledger and balance.
   - Sent notifications (mocked dunning emails).
8. **Plans** (`/plans`) — catalog: name, price, interval, trial days. Create and archive.
   The price of a plan in use can't be edited; create a new plan instead.
9. **Invoices list** (`/invoices`) — filter by status (`open` / `paid` / `void` /
   `uncollectible`) and subscription.
10. **Invoice detail** (`/invoices/:id`)
    - Line items, with proration lines highlighted.
    - Payment attempts with `failure_code`.
    - Refunds, with a "Partial refund" action (amount ≤ paid − already refunded).
    - "Retry payment" action when the invoice is `open`.
11. **Webhook inbox** (`/webhooks`) — visible proof of idempotency.
    - List: `event_id`, type, `processing_status`, `duplicate_deliveries_count`,
      `received_at`, error.
    - Payload viewer.
    - "Reprocess" only for `failed` events. Trying it on a `processed` event shows the refusal.
12. **Scenario Lab / Event simulator** (`/simulator`) — the demo stage; acts as the fake Stripe.
    - Run canned scenarios: happy path, failure and recovery, full dunning, duplicate
      webhook, out-of-order events, lost event, upgrade, downgrade with credit, expired
      card, partial refund.
    - Emit a manual event (type + subscription) with "deliver", "drop" (creates a
      discrepancy) and "deliver N times" options.
    - Redeliver an already delivered event.
    - Reset and reseed the database.
13. **Dunning board** (`/dunning`) — dunning cases in columns per stage (day 0 notice,
    day 3 retry, day 7 suspended, day 14 canceled / recovered).
    - Each card: subscription, invoice, next step and date.
    - Link to the subscription.
14. **Reconciliation** (`/reconciliation`)
    - Run list and "Run now" button.
    - Run detail with discrepancies: kind, field, internal vs expected value, evidence events.
    - Per-discrepancy actions: "Apply expected" (goes through the state machine and is
      audited) or "Acknowledge" (with a note).
15. **Global audit log** (`/audit`) — every billing event, filterable by type, source and
    date range. Complements screen 4.

## 9. API endpoints (Rails, `/api/v1`)

Standard error shape:

```json
{ "error": { "code": "invalid_transition", "message": "Cannot pause a canceled subscription",
             "details": { "from": "canceled", "to": "paused", "allowed": [] } } }
```

Every list endpoint answers `{ "data": [...], "meta": { "page", "per_page", "total_count",
"total_pages" } }` (50 per page).

HTTP codes: 422 for business-rule violations, 409 for `lock_version` conflicts or an
idempotency key reused with a different payload, 404 as usual. State-changing POSTs accept
an `Idempotency-Key` header.

### Plans
- `GET /plans?include_archived=` — list plans (active only by default).
  Response item: `{ "id": 1, "code": "pro_monthly", "name": "Pro", "amount_cents": 19900, "currency": "USD", "interval": "month", "trial_days": 7, "active": true, "archived_at": null }`
- `GET /plans/:id`
- `POST /plans` — create a plan.
  Request: `{ "code": "pro_monthly", "name": "Pro", "amount_cents": 19900, "interval": "month", "trial_days": 7 }`
- `POST /plans/:id/archive` — remove from the catalog without affecting current subscribers.

### Customers
- `GET /customers?q=`
- `GET /customers/:id` — includes `credit_balance_cents` and `payment_methods`
  (`subscriptions` added in plan 04).
- `POST /customers`
  Request: `{ "name": "Studio Flow", "email": "owner@studioflow.test" }`
- `POST /customers/:id/payment_methods` — attach a test card. 422 `card_expired` if the
  expiry date has already passed (simulated time).
  Request: `{ "test_card": "pm_card_chargeDeclinedInsufficientFunds", "exp_month": 12, "exp_year": 2027, "default": true }`
- `POST /customers/:id/payment_methods/:pm_id/make_default`
- `GET /customers/:id/credit_ledger_entries`
  Response item: `{ "amount_cents": 5000, "balance_after_cents": 5000, "reason": "downgrade_proration", "invoice_id": 12, "note": null, "occurred_at": "..." }`
- `POST /customers/:id/credit_ledger_entries` — manual adjustment by the operator.
  Request: `{ "amount_cents": -2500, "note": "Correction" }`. 422 `insufficient_credit` if the
  balance would go below zero.
- `GET /customers/:id/notifications`

### Subscriptions
- `GET /subscriptions?status=past_due&q=&page=` (`q` searches customer name / email)
- `POST /subscriptions`
  Request: `{ "customer_id": 1, "plan_id": 2 }` — the plan decides: `trial_days > 0` starts
  `trialing`, otherwise `active`. 422 `plan_archived` / `customer_already_subscribed`.
- `GET /subscriptions/:id`
  ```json
  { "id": 7, "status": "active", "plan": {}, "current_period_start": "...", "current_period_end": "...",
    "trial_ends_at": null, "cancel_at_period_end": false, "access_suspended": false,
    "lock_version": 4, "allowed_actions": ["cancel_now", "cancel_at_period_end", "pause"],
    "open_dunning_case": null }
  ```
- `POST /subscriptions/:id/cancel`
  Request: `{ "at_period_end": true, "lock_version": 4 }`
- `POST /subscriptions/:id/undo_cancel` — removes a scheduled cancellation.
  Request: `{ "lock_version": 5 }`
- `POST /subscriptions/:id/pause` — Request: `{ "resumes_at": "2026-11-01", "lock_version": 4 }`
  (`resumes_at` optional, must be in the future)
- `POST /subscriptions/:id/resume` — Request: `{ "lock_version": 6 }`
- Every action requires `lock_version` (409 if stale) and returns the updated subscription;
  an action missing from `allowed_actions` answers 422 `action_not_allowed`.
- `POST /subscriptions/:id/plan_change_preview` — computes without persisting.
  Request: `{ "plan_id": 3, "strategy": "immediate" }`
  ```json
  { "proration_date": "...", "remaining_ratio": "0.5333",
    "lines": [ { "kind": "proration_credit", "amount_cents": -10613 },
               { "kind": "proration_charge", "amount_cents": 5280 } ],
    "net_cents": -5333, "credit_to_balance_cents": 5333, "amount_due_now_cents": 0 }
  ```
- `POST /subscriptions/:id/plan_changes` — executes the change. Same payload as the preview
  plus `proration_date` and `lock_version`, so the charged amount matches what was shown.
  Response: `{ "plan_change": {}, "invoice": {} | null }`
- `GET /subscriptions/:id/plan_changes`
- `GET /subscriptions/:id/state_transitions`
  Response: `{ "data": [{ "from_status": "active", "to_status": "past_due", "reason": "payment_failed", "actor_type": "webhook", "webhook_event_id": 88, "billing_event_id": 120, "occurred_at": "..." }] }`
- The audit timeline (screen 4) uses `GET /billing_events?subscription_id=`: every
  transition is also a billing event, so no separate endpoint is needed.

### Invoices
- `GET /invoices?status=&subscription_id=`
- `GET /invoices/:id` — includes `line_items`, `payment_attempts`, `refunds`.
- `POST /invoices/:id/retry_payment` — asks the fake Stripe for a new charge. The result
  comes back as a webhook; there is no synchronous shortcut.
- `POST /invoices/:id/refunds`
  Request: `{ "amount_cents": 5000, "reason": "requested_by_customer", "destination": "original_method" | "credit_balance" }`
  Response: the refund. 422 if the amount exceeds what is still refundable.

### Webhooks
- `POST /webhooks/stripe` — ingestion, Stripe-shaped payload:
  ```json
  { "id": "evt_1Q...", "type": "invoice.payment_failed", "created": 1790000000,
    "data": { "object": { "id": "in_...", "subscription": "sub_...", "attempt_count": 1 } } }
  ```
  Responses: `200 { "status": "processed" | "duplicate" | "skipped_stale" | "ignored_unhandled" }`
  and `500 { "status": "failed" }` (so the provider retries); 400 `invalid_payload` for a body
  that isn't a readable event. Duplicates also get 200, otherwise the provider keeps
  retrying. Signature verification sits behind an interface that is a no-op today.
- `GET /webhook_events?status=&event_type=&page=`
- `GET /webhook_events/:id` — includes `payload` and the billing events the event caused.
- `POST /webhook_events/:id/reprocess` — `failed` or `received` only. Otherwise 422
  `already_processed`.

### Dunning
- `GET /dunning_cases?status=open`
- `GET /dunning_cases/:id`
  Response: `{ "status": "open", "current_step": "day_3_retry", "next_step_at": "...", "steps": [ { "step": "day_0_notice", "executed_at": "...", "outcome": "notified" } ] }`

### Reconciliation
- `POST /reconciliation_runs` — Request: `{ "subscription_id": null }` (null = everything).
  Response: `{ "id": 3, "status": "completed", "subscriptions_checked": 42, "discrepancies_found": 2 }`
- `GET /reconciliation_runs`
- `GET /reconciliation_runs/:id` — includes discrepancies.
- `POST /reconciliation_discrepancies/:id/resolve`
  Request: `{ "strategy": "apply_expected" | "acknowledge", "note": "..." }`

### Audit
- `GET /billing_events?subscription_id=&customer_id=&event_type=&actor_type=&from=&to=&page=`
  (`from` / `to` are inclusive `YYYY-MM-DD` dates on `occurred_at`).
  Response: `{ "data": [...], "meta": { "page", "per_page", "total_count", "total_pages", "event_types" } }`

### Dashboard
- `GET /dashboard/summary`
  Response: `{ "by_status": { "active": 30, "past_due": 4 }, "mrr_cents": 597000, "open_discrepancies": 2, "open_dunning_cases": 4, "recent_events": [] }`

### Simulator (fake Stripe; mounted only when `SIMULATOR_ENABLED`)
- `GET /simulator/clock` — Response: `{ "now": "2026-10-01T00:00:00Z" }`
- `GET /simulator/test_cards` — the test card catalog (token, brand, last4, behavior).
- `POST /simulator/clock/advance` — Request: `{ "days": 3 }`
  Response: `{ "now": "...", "tick_report": { "renewals": 5, "trials_ended": 1, "dunning_steps_executed": 2, "events_emitted": 9 } }`
- `POST /simulator/clock/reset`
- `GET /simulator/scenarios` — Response: `[{ "key": "duplicate_webhook", "title": "...", "description": "..." }]`
- `POST /simulator/scenarios/:key/run`
  Response: `{ "scenario_run_id": 4, "subscription_id": 9, "events": [] }`
- `POST /simulator/events` — emit a manual event.
  Request: `{ "type": "invoice.paid", "subscription_id": 9, "delivery": "deliver" | "drop", "copies": 1 }`
- `POST /simulator/events/:id/deliver` — deliver a dropped event, or redeliver (duplicate).
- `GET /simulator/events` — the fake Stripe outbox.
- `POST /simulator/reset` — wipe and reseed the database.

## 10. Database schema (draft)

Every table has `id` and `created_at`. Append-only tables have no `updated_at` and are
protected in two layers: `readonly?` on the model and **SQLite triggers
`BEFORE UPDATE/DELETE → RAISE(ABORT)`**, so the database enforces immutability even if
someone calls `update_column`.

### Catalog and customers

**plans**
- `code` (unique), `name`, `amount_cents`, `currency`, `interval` (month/year), `trial_days`,
  `archived_at`
- `code`, `amount_cents`, `currency` and `interval` are read-only after create.

**customers**
- `name`, `email` (unique), `provider_customer_id` (unique, `cus_...`)
- `credit_balance_cents` — cache derived from the ledger, recomputed in the same transaction.

**payment_methods**
- `customer_id`, `provider_payment_method_id` (unique), `brand`, `last4`, `exp_month`, `exp_year`
- `test_card_token` — Stripe test-mode token (e.g. `pm_card_chargeDeclinedInsufficientFunds`).
  The behavior (`succeeds` / `card_declined` / `insufficient_funds` / `expired_card` /
  `succeeds_after_failures`) is derived from it for display; no column stores it. The fake
  provider receives the token as a call argument and decides outcomes from it.
- `is_default` — at most one per customer (partial unique index).

**credit_ledger_entries** (append-only)
- `customer_id`, `amount_cents` (+ credit / − debit, never 0)
- `balance_after_cents` — running balance after the entry, never negative
- `reason`: `downgrade_proration` / `applied_to_invoice` / `refund_to_balance` / `manual_adjustment`
  (each reason only moves the balance in its own direction; manual adjustments go both ways)
- `invoice_id` (nullable), `plan_change_id` (nullable), `note`
- `occurred_at` (simulated time)

### Subscription

**subscriptions**
- `customer_id`, `plan_id`, `provider_subscription_id` (unique)
- `status`: `trialing` / `active` / `past_due` / `paused` / `canceled`
- `current_period_start`, `current_period_end`, `trial_ends_at`
- `cancel_at_period_end`, `canceled_at`, `cancellation_reason`
- `paused_at`, `resumes_at`, `access_suspended_at`
- `last_provider_event_at` — used to discard out-of-order events.
- `lock_version` — optimistic locking.
- Indexes on `status` and `current_period_end`; partial unique index on `customer_id` where
  `status <> 'canceled'` (one live subscription per customer).
- `status` can only change through `Subscriptions::Transition`; the model raises otherwise.

**subscription_state_transitions** (append-only)
- `subscription_id`, `from_status` (null on creation), `to_status`
- `reason`: `trial_converted` / `payment_failed` / `payment_recovered` / `customer_requested` /
  `dunning_exhausted` / `reconciliation_correction` / ...
- `actor_type`: `webhook` / `admin` / `system_job` / `reconciliation` (same vocabulary as
  `billing_events`)
- `webhook_event_id` (nullable), `billing_event_id`, `occurred_at` (simulated clock time),
  `metadata` (json)
- Index on (`subscription_id`, `occurred_at`).

**plan_changes**
- `subscription_id`, `from_plan_id`, `to_plan_id`
- `strategy` (`immediate` / `at_period_end`), `status` (`scheduled` / `applied` / `canceled`)
- `proration_date`, `effective_at`
- `credit_cents`, `charge_cents`, `net_cents`
- `invoice_id` (nullable)

### Billing

**invoices**
- `subscription_id`, `customer_id`, `provider_invoice_id` (unique), `number`
- `status`: `draft` / `open` / `paid` / `void` / `uncollectible`
- `billing_reason`: `subscription_create` / `subscription_cycle` / `subscription_update` / `manual`
- `period_start`, `period_end`
- `subtotal_cents`, `credit_applied_cents`, `total_cents`, `amount_paid_cents`,
  `amount_refunded_cents`, `amount_due_cents`, `currency`
- `due_at`, `paid_at`, `attempt_count`
- `last_provider_event_at` — stale-event detection is per object, so invoices need their own
  ordering marker (an old event for invoice A must not be discarded because of invoice B).

**invoice_line_items**
- `invoice_id`
- `kind`: `subscription` / `proration_credit` / `proration_charge` / `credit_applied`
- `description`, `plan_id`, `amount_cents` (negative for credits), `period_start`, `period_end`

**payment_attempts** (append-only)
- `invoice_id`, `payment_method_id`, `provider_charge_id` (unique)
- `status` (`succeeded` / `failed`), `failure_code` (`card_declined` / `expired_card` /
  `insufficient_funds`)
- `amount_cents`, `attempted_at`, `dunning_step_id` (nullable)

**refunds**
- `invoice_id`, `payment_attempt_id`, `provider_refund_id` (unique)
- `amount_cents`, `destination` (`original_method` / `credit_balance`), `reason`, `status`
- The sum of refunds never exceeds `amount_paid_cents` — validated in the model, inside a
  transaction.

### Dunning

**dunning_cases**
- `subscription_id`, `invoice_id` (unique while open)
- `status`: `open` / `recovered` / `exhausted` / `canceled`
- `started_at`, `current_step`, `next_step_at`, `closed_at`, `closed_reason`

**dunning_steps** (append-only)
- `dunning_case_id`, `step` (`day_0_notice` / `day_3_retry` / `day_7_suspend` / `day_14_cancel`)
- `scheduled_at`, `executed_at`, `outcome`
- **unique (`dunning_case_id`, `step`)** — if the job runs twice, the step doesn't repeat.

**customer_notifications** (mocked email outbox)
- `customer_id`, `kind`, `subject`, `body`, `dunning_step_id` (nullable), `sent_at`

### Webhooks and idempotency

**mocked_webhook_events** (fake Stripe outbox — source of truth for "expected" state)
- `event_id` (unique, `evt_...`), `event_type`, `api_version`, `payload` (json)
- `provider_object_id` (`sub_...` / `in_...`), `provider_subscription_id` (indexed),
  `provider_created_at`
- `delivery_status` (`pending` / `delivered` / `dropped`), `delivery_count`, `scenario_run_id`

**webhook_events** (our inbox — where idempotency lives)
- `provider_event_id` (**UNIQUE**), `event_type`, `provider_object_id`, `payload`,
  `provider_created_at`, `received_at` (simulated time)
- `processing_status`: `received` / `processed` / `failed` / `skipped_stale` / `ignored_unhandled`
- `processed_at`, `attempts`, `last_error`, `duplicate_deliveries_count`
- Flow: `INSERT … ON CONFLICT(provider_event_id) DO NOTHING` claims the row. Processing then
  runs in a second transaction that locks and re-reads the row: if it is already terminal,
  it's a duplicate (counter + 200); otherwise the handler's side effects and the terminal
  status commit together. A handler failure is recorded in a third transaction.
- No foreign keys point here from `billing_events` / `subscription_state_transitions`:
  those are append-only tables, and adding a foreign key in SQLite rebuilds the table and
  drops its triggers.
- Second layer: unique `provider_invoice_id` and `provider_charge_id`, so two *different*
  events describing the same fact don't duplicate either.

**idempotency_keys** (for our own API POSTs)
- `key` (unique), `request_fingerprint` (SHA-256 of method, path and body), `response_status`,
  `response_body` (both null while the first request runs; 5xx responses are not kept, so a
  retry can run again)

### Reconciliation, audit and simulation

**billing_events** (general audit log, append-only)
- `subject_type`, `subject_id` (polymorphic, nullable) — what the event is about; many events
  concern records that are neither a subscription nor a customer (plans, invoices, the clock).
- `subscription_id` (nullable), `customer_id` (nullable) — denormalized for timeline queries
- `event_type`: `subscription.created` / `subscription.transitioned` / `plan.changed` /
  `invoice.issued` / `payment.failed` / `refund.issued` / `dunning.step_executed` /
  `discrepancy.detected` / ...
- `actor_type` (`webhook` / `admin` / `system_job` / `reconciliation`),
  `webhook_event_id` (nullable)
- `data` (json with `before` / `after`), `occurred_at`
- Hash chain (`previous_hash`, `entry_hash`) is a future improvement — see section 7.

**reconciliation_runs**
- `status`, `scope_subscription_id` (nullable), `triggered_by`, `started_at`, `finished_at`,
  `subscriptions_checked`, `discrepancies_found`

**reconciliation_discrepancies**
- `reconciliation_run_id`, `subscription_id`
- `kind`: `status_mismatch` / `period_mismatch` / `plan_mismatch` / `missing_invoice` /
  `invoice_amount_mismatch` / `invoice_status_mismatch` / `undelivered_event` / `failed_event`
- `field`, `internal_value`, `expected_value`, `evidence_event_ids` (json)
- `resolution_status` (`open` / `resolved` / `acknowledged`), `resolved_at`, `resolution_note`
- The expected value comes from a pure projection: replaying every outbox event for that
  subscription, ordered by `provider_created_at`.

**simulation_clock** (single row): `current_time`

**scenario_runs**: `scenario_key`, `status`, `started_at`, `log` (json)

## 11. Next steps

1. Project structure (Rails + Vue folders, conventions, tooling).
2. README skeleton with the state machine diagram and "Edge cases handled".
3. Implementation, phase by phase, each approved before the next.
