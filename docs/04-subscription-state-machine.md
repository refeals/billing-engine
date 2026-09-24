# 04 — Subscription state machine

## Goal

Subscriptions with a strict state machine: every status change goes through a single
transition path that validates it, records it and audits it.

## Depends on

- `03-catalog-and-customers.md`

## Scope

**In**
- Tables: `subscriptions`, `subscription_state_transitions`, `idempotency_keys`.
- The state machine itself and its single write path.
- Admin actions: create (with trial), cancel (now / at period end), pause, resume.
- Tick steps: `cancel_at_period_end` reached, `resumes_at` reached.
- API idempotency keys for state-changing POSTs.
- Screens 2, 3 (without billing tabs) and 4.

**Out**
- Creating a subscription without trial (needs a first invoice — plan 07).
- Transitions caused by payments (`past_due`, recovery — plans 07 and 10).
- Plan changes (plan 08).

## Provisional behavior until plan 07 (replaced)

Plan 07 replaced this: trials end with an invoice, renewals invoice, and a subscription
without a trial is billed at creation. Kept here for the history of the decision.

To make pause, resume and the ticks demonstrable before invoicing exists:
- a plan without a trial creates the subscription already `active` (first period not charged);
- `Ticks::EndTrials` converts `trialing → active` when the trial ends, without charging;
- `Ticks::RenewPeriods` rolls an active subscription's period forward when it ends, without
  charging, so period dates (and "cancel at period end") never point to the past.

Plan 07 replaces both with an invoice, and the conversion then waits for the payment webhook.

## Backend

### Transition table

| From | To | Reasons |
|---|---|---|
| (none) | `trialing` | `subscription_created` |
| (none) | `active` | `subscription_created` (no trial, plan 07) |
| `trialing` | `active` | `trial_converted` |
| `trialing` | `past_due` | `payment_failed` |
| `trialing` | `canceled` | `customer_requested`, `period_ended_after_cancel_request` |
| `active` | `past_due` | `payment_failed` |
| `active` | `paused` | `customer_requested` |
| `active` | `canceled` | `customer_requested`, `period_ended_after_cancel_request` |
| `past_due` | `active` | `payment_recovered` |
| `past_due` | `canceled` | `dunning_exhausted`, `customer_requested`, `period_ended_after_cancel_request` |
| `paused` | `active` | `customer_requested`, `pause_ended` |
| `paused` | `canceled` | `customer_requested` |
| `canceled` | — | terminal |

`reconciliation_correction` is accepted as an extra reason on any valid edge (plan 11); it
never unlocks an edge that isn't in the table.

The Mermaid version of this table goes into the README.

### Single write path
- Hand-written `SubscriptionStateMachine` (no AASM). The table above is a frozen constant, and
  the whole machine is small enough that a gem would hide more than it saves. It also keeps
  the audit write in the same method, where it can't be skipped.
- `Subscriptions::Transition.call(subscription, to:, reason:, source:, webhook_event: nil,
  metadata: {})`:
  1. Validates the edge and the reason; raises `InvalidTransitionError` with `from`, `to` and
     `allowed` otherwise.
  2. In one transaction: updates `status` (with `lock_version`), inserts a
     `subscription_state_transitions` row, and calls `Audit.record`
     (`subscription.transitioned`).
- `status` is not in any `permit` list and the model raises if `status` changes outside
  `Transition` (guarded by a flag set only inside it).

### `subscriptions`
- Columns as in `00-prompt.md` §10. FK from `billing_events.subscription_id` added here.
- `Subscription#allowed_actions`: derived from state plus flags (e.g. no `pause` when
  `cancel_at_period_end` is set). This is what the frontend renders buttons from.

### `subscription_state_transitions` (append-only)
- Columns as in `00-prompt.md` §10.

### Admin actions (services)
- `Subscriptions::Create` — trial only in this plan. `trial_ends_at = now + plan.trial_days`.
  Rejects archived plans and a customer with another non-canceled subscription.
- `Subscriptions::Cancel` — `at_period_end: true` only sets the flag (audited, no
  transition); `false` transitions now.
- `Subscriptions::UndoCancel` — removes a scheduled cancellation.
- `Subscriptions::Pause` / `Resume` — optional `resumes_at`.
- All take `lock_version` from the client; a mismatch is a 409.

### Tick steps
- `Ticks::CancelAtPeriodEnd` — period end reached and flag set → `canceled`
  (`period_ended_after_cancel_request`, actor `system_job`).
- `Ticks::EndTrials` — provisional (see above).
- `Ticks::ResumePaused` — `resumes_at` reached → `active` (`pause_ended`).
- Order: cancel-at-period-end runs before trial conversion, so a trial scheduled to cancel
  ends instead of converting.

### API idempotency keys
- `idempotency_keys` table as in `00-prompt.md` §10.
- Controller concern `Idempotent`: with an `Idempotency-Key` header, the first request stores
  the response; a replay with the same body returns the stored response; a replay with a
  different body returns 409 `idempotency_key_reused`. Protects double-clicks on
  "Cancel" and "Change plan".

### Endpoints
From `00-prompt.md` §9, **Subscriptions**: list, create, show, cancel, undo_cancel, pause,
resume, `state_transitions`. The timeline reads `GET /billing_events?subscription_id=`.
Transition rows use `actor_type` (same vocabulary as `billing_events`).

## Frontend

- Screen 2 **Subscriptions list** with status filter and search; "New subscription" dialog
  (customer, plan).
- Screen 3 **Subscription detail**: header, action buttons from `allowed_actions`,
  confirmation dialogs, 409 handling ("changed elsewhere, reload"). Billing tabs are
  placeholders until their plans.
- Screen 4 **Audit timeline** (`/subscriptions/:id/history`): transitions and billing events
  merged by `occurred_at`, reusing `AuditEventItem` from plan 02.
- `StatusBadge` component with one color per state, used everywhere.
- Customer detail (plan 03) now lists the customer's subscriptions.

## Tests

- Every edge in the table is allowed; every other pair is refused (generated from the
  constant, so a new state can't be added without covering it).
- Direct `update(status: …)` raises.
- A transition writes exactly one transition row and one billing event, or nothing.
- Stale `lock_version` → 409.
- Idempotency key: replay returns same response, different body → 409.
- Ticks: cancel at period end and pause end fire on the right day.

## Documentation

- README: state machine Mermaid diagram and a short explanation of the single write path.
- README "Edge cases handled": invalid transition attempt; concurrent edits (optimistic
  lock); double submit (idempotency key); cancel at period end; pause with automatic resume.

## Acceptance criteria

- Create a trialing subscription, pause / resume / cancel it from the UI; each change shows
  up in the timeline.
- Invalid actions are not offered by the UI and are refused by the API.
