# 07 — Invoicing and payments

## Goal

The money cycle: invoices are generated on subscription start, trial end and renewal, charged
through the gateway, and settled by webhooks that drive the subscription state.

## Depends on

- `06-fake-payment-provider.md`

## Scope

**In**
- Tables: `invoices`, `invoice_line_items`, `payment_attempts`.
- Invoice generation, numbering, applying customer credit.
- Charging through the gateway; `invoice.paid` / `invoice.payment_failed` /
  `charge.succeeded` / `charge.failed` handlers.
- Subscription creation without trial.
- Tick steps: trial end, renewal.
- Manual retry payment.
- Screens 9 and 10 (without refunds); Invoices tab on screen 3.

**Out**
- Proration lines (plan 08), refunds (plan 09), the dunning schedule (plan 10). In this plan a
  failed payment only moves the subscription to `past_due`.

## Backend

### Tables
- `invoices`, `invoice_line_items`, `payment_attempts` as in `00-prompt.md` §10.
- `invoices.last_provider_event_at` is used for per-object stale detection (plan 05).
- `payment_attempts` is append-only.
- `invoices.number`: sequential and gap-free per year (`BE-2026-000123`), generated inside the
  invoice's transaction.

### Invoice lifecycle
- `draft` → `open` (finalized, amounts frozen) → `paid` | `void` | `uncollectible`.
- Amounts can't change after `open`. Any correction is a new document (credit, refund), never
  an edit.
- `Invoices::Build` creates line items; `Invoices::Finalize` computes totals, applies credit
  balance (a `credit_applied` line and a ledger debit, same transaction), registers the
  invoice at the gateway and opens it.
- If total after credit is zero, the invoice is marked `paid` directly without a charge.

### Flows

This plan replaces the provisional behavior from plan 04: `Ticks::EndTrials` stops converting
trials without charging, `Ticks::RenewPeriods` is replaced by `Ticks::Renew` (which invoices),
and subscriptions created without a trial get their first invoice.

- **Create without trial:** `(none) → active` with the first invoice charged immediately.
  If that first payment fails, `active → past_due`. Decision: no `incomplete` state; it's not
  in the agreed state list and `past_due` + dunning covers it.
- **Trial end** (`Ticks::EndTrials`): invoice for the first period. The subscription stays
  `trialing` until the webhook arrives: `invoice.paid` → `trialing → active`;
  `invoice.payment_failed` → `trialing → past_due`.
- **Renewal** (`Ticks::Renew`): for `active` subscriptions whose period ended and without
  `cancel_at_period_end`: roll the period, invoice, charge. `past_due` and `paused`
  subscriptions are not renewed.
- **Payment webhooks:**
  - `invoice.paid` → invoice `paid`, `amount_paid_cents`, payment attempt `succeeded`; if the
    subscription is `past_due` → `active` (`payment_recovered`).
  - `invoice.payment_failed` → attempt `failed` with `failure_code`, `attempt_count + 1`;
    subscription `active`/`trialing` → `past_due`.
  - Domain-level idempotency: unique `provider_charge_id` means two different events about the
    same charge can't create two attempts.
- **Retry payment** (`POST /invoices/:id/retry_payment`): only `open` invoices, uses the
  current default card; the result comes by webhook.

### Decisions taken during implementation
- **One settlement path.** Even a $0 invoice (covered by credit) goes to the provider, which
  answers `invoice.paid` without a charge. The engine never marks an invoice paid itself.
- **No persisted `draft`.** Lines, credit, number and provider id are created in one
  transaction, so an invoice is `open` from its first commit.
- **Attempts from either event.** `charge.*` and `invoice.*` both record the payment attempt;
  the unique `provider_charge_id` makes whichever arrives second a no-op.
- **No card is a payment failure** (`no_payment_method`), reported by the provider like any
  other.
- **Pause stops the billing clock.** On resume, a period that ended during the pause is
  replaced by a new one starting at the resume moment, billed right away.
- **Gap-free numbers** via a per-year counter incremented in the invoice's transaction.

### Known limitation (closed by plan 10: dunning cancels on day 14)
A subscription that stays `past_due` longer than a whole period and then recovers is billed
for the elapsed periods, one per daily tick. Dunning (plan 10) cancels a `past_due`
subscription on day 14, so with monthly and yearly plans this can't happen once it exists.

## Frontend

- Screen 9 **Invoices list**.
- Screen 10 **Invoice detail**: line items, totals breakdown (subtotal, credit applied,
  total, paid, due), payment attempts with failure codes, "Retry payment" button.
- Screen 3: Invoices tab and Payment method tab (current default card, expired badge).

## Tests

- Trial end with a good card → `active` after the webhook, not before.
- Trial end with a declining card → `past_due`.
- Renewal happens on the right tick; not for `past_due`/`paused`/`cancel_at_period_end`.
- Card expires between two renewals → second charge fails with `expired_card`.
- Credit balance covers the whole invoice → `paid` without charge; covers part → reduced
  charge; ledger and invoice agree.
- Open invoice amounts can't be edited.
- Duplicate `invoice.paid` (different event ids, same charge) → one payment attempt.

## Documentation

- README "Edge cases handled": expired card at renewal; credit covering all or part of an
  invoice; payment result only trusted from the webhook; same charge reported twice.

## Acceptance criteria

- Create a trial subscription, advance the clock past the trial, see the invoice paid and the
  subscription `active`; with a declining card see it `past_due`.
