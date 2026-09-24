# 03 — Catalog and customers

## Goal

Plans, customers, payment methods and the customer credit ledger: the static data every
billing flow reads.

## Depends on

- `02-audit-log.md`

## Scope

**In**
- Tables: `plans`, `customers`, `payment_methods`, `credit_ledger_entries`.
- CRUD-ish endpoints for plans and customers, attaching test cards.
- Screens 6, 7 and 8.

**Out**
- Registering customers and cards at the provider (plan 06 adds the gateway calls; until
  then `provider_*_id` values are generated locally with the same prefixes).
- Writing credit entries from real flows (plans 07, 08, 09). This plan only builds the
  ledger and its read side.

## Backend

### `plans`
- Columns as in `00-prompt.md` §10. `currency` always `USD` (validated).
- `amount_cents` and `interval` are immutable after create. Changing the price of an existing
  plan would silently change what current subscribers pay; a new plan is the explicit way.
- `archive` sets `archived_at`; archived plans can't be chosen for new subscriptions or plan
  changes but keep working for existing subscribers.

### `customers`
- `name`, `email` (unique, case-insensitive), `provider_customer_id` (`cus_…`).
- `credit_balance_cents`: cache of the ledger sum, updated in the same transaction as each
  ledger insert. A consistency check (`Customer#ledger_balance_matches?`) is used by tests and
  later by reconciliation.

### `payment_methods`
- Test cards follow Stripe test-mode convention: the provider token decides the behavior,
  e.g. `pm_card_visa` (succeeds), `pm_card_chargeDeclinedInsufficientFunds`,
  `pm_card_chargeDeclinedExpiredCard`, `pm_card_succeedsAfterFailures_2`.
- `simulated_behavior` is stored for display only; it is derived from the token. The fake
  provider (plan 06) reads the token, not our column, so provider behavior doesn't depend on
  our database.
- `exp_month`, `exp_year`; `PaymentMethod#expired?(at: BillingClock.now)`. Because the clock
  moves, a card can expire in the middle of a subscription. That's a real edge case the demo
  can show.
- Exactly one default per customer, enforced by a partial unique index
  (`WHERE is_default = 1`).

### `credit_ledger_entries` (append-only, plan 02 mechanism)
- Columns as in `00-prompt.md` §10.
- `CreditLedger.credit!(customer, amount_cents, reason:, ...)` and `debit!` are the only
  write path. `debit!` refuses to take the balance below zero.
- Every entry writes a `billing_events` row (`credit.granted` / `credit.applied`).

### Endpoints
As in `00-prompt.md` §9, **Plans** and **Customers**, except `GET /customers/:id/notifications`
(plan 10).

## Frontend

- Screen 8 **Plans**: list, create form, archive with confirmation. Price field in dollars,
  converted to cents at the API boundary only.
- Screen 6 **Customers list**: search, create.
- Screen 7 **Customer detail**: payment methods (add test card from a select of known
  tokens, set default, expired badge computed from the simulated date), credit balance and
  ledger table. Subscriptions section is a placeholder until plan 04.

## Tests

- Plan price and interval can't be changed; archived plan can't be subscribed.
- Only one default payment method per customer (DB-level).
- `expired?` flips when the clock crosses the expiry month.
- Ledger: debit below zero is refused; cache matches sum; ledger rows are immutable.

## Documentation

- README "Architecture decisions": test cards by token (mirrors Stripe test mode).
- README "Edge cases handled": card that expires while the subscription is running
  (behavior completed in plans 07 and 10); plan price changes don't affect current
  subscribers.

## Acceptance criteria

- Can create plans and customers, attach cards and see them in the UI.
- Credit ledger visible (empty for now) with balance derived from entries.
