# 12 — Scenario Lab and seeds

## Goal

Make every hard case reproducible with one click, and give the app realistic data on first
run. This is what a reviewer will actually use to evaluate the project.

## Depends on

- `11-reconciliation.md`

## Scope

**In**
- Seed data.
- Canned scenarios and `scenario_runs`.
- Reset / reseed endpoint.
- Final version of screen 12.

**Out**
- New domain behavior. Scenarios only compose what previous plans built.

## Backend

### Seeds
- Plans for a fictional studio product: `Starter`, `Studio`, `Studio Pro` (monthly), and one
  yearly plan.
- ~20 customers spread across every state: trialing, active, past_due at different dunning
  stages, paused, canceled, with credit balance, with refunds.
- Built **through the services and the simulated clock** (create, advance, fail, pay), never by
  inserting rows directly. The audit trail and the provider outbox are then coherent from the
  first run and reconciliation starts at zero discrepancies.
- The seed run is deterministic (fixed start date, fixed ordering), so screenshots and README
  examples stay valid.

### Scenarios
- `Scenarios::Base` with a small step DSL: `create_customer`, `attach_card`, `subscribe`,
  `advance_days`, `emit`, `drop_next`, `change_plan`, `refund`, `expect`.
- Each run creates its own customer (so scenarios don't interfere) and records every step in
  `scenario_runs.log`.
- Scenarios advance the shared clock; this affects every subscription, which is documented
  and accepted.
- List:
  1. `happy_path` — trial, conversion, two renewals.
  2. `failed_payment_recovery` — renewal fails, card updated on day 4, recovered.
  3. `full_dunning` — renewal fails, never recovers, canceled on day 14.
  4. `duplicate_webhook` — `invoice.paid` delivered three times.
  5. `out_of_order_events` — `invoice.payment_failed` delivered after `invoice.paid`.
  6. `lost_webhook` — `invoice.paid` dropped; reconciliation flags it.
  7. `upgrade_mid_cycle` — upgrade on day 10 of 30.
  8. `downgrade_with_credit` — downgrade mid-cycle, credit consumed at renewal.
  9. `expired_card` — card expires before renewal, dunning starts.
  10. `partial_refund` — two partial refunds, over-refund refused.
- Each scenario ends with `expect` assertions. The same scenarios run in the test suite, so the
  demo can't silently rot.

### Endpoints
From `00-prompt.md` §9, **Simulator**: scenarios list and run, `POST /simulator/reset`.
Reset drops all data, resets the clock and runs the seeds.

## Frontend

- Screen 12 **Scenario Lab**, final version:
  - Scenario cards: title, what it demonstrates, "Run".
  - After running: step log, links to the subscription, its timeline, inbox and outbox
    entries.
  - Manual events and outbox from plan 06 kept as an "Advanced" section.
  - "Reset demo data" with a confirmation dialog.

## Tests

- Every scenario runs green as an integration test.
- Seeds → reconciliation reports zero discrepancies.
- Seeds are deterministic (two runs produce the same summary).

## Documentation

- README "Try it" section: a guided tour of 3–4 scenarios with what to look at in each.
- Each entry in "Edge cases handled" links to the scenario and/or test that proves it.

## Decisions taken during implementation

- **Fixed demo calendar.** `BillingClock.travel_to!(time)` is the only sanctioned rewind
  besides the clock reset, used by the seeds and the demo reset. Seeds start on 2026-01-05
  09:00 UTC and replay 70 simulated days of "stories" (`day → actions`, 20 studios). Provider
  ids stay random; the summary is deterministic and asserted exactly in the seed spec.
- **Shared plan catalog** (`Demo::Catalog`): Starter $29/mo (14-day trial), Studio $59/mo,
  Studio Pro $99/mo, Studio Annual $590/yr. Scenarios find or create them by code, so they
  work with or without seeds.
- **Reset deletes everything.** Append-only triggers are read from `sqlite_master`, dropped,
  every table emptied inside one transaction (`PRAGMA defer_foreign_keys`), sequences reset
  and the triggers recreated from the captured SQL before the transaction commits; then the
  seeds run. The request must send `confirm: "reset"`. It takes about 15 seconds.
- **Step DSL** (`Scenarios::Base`): `customer`, `card`, `subscribe`, `advance_days`,
  `advance_to_period_end`, `drop_next`, `deliver_dropped`, `redeliver`, `change_plan`,
  `refund`, `retry_payment`, `reconcile`, `expect_that`, `expect_refused`. A failed check or
  an unexpected error marks the run `failed` with the message; the API still answers 201.
- **Runs are linked to what they caused.** `Current.scenario_run` tags every outbox event
  with `scenario_run_id`; the run's own events are those tagged *and* for its subscription,
  because the shared clock renews other subscriptions during the run. `drop_next` also goes
  through `Current` (one shot: the next event of that type is created dropped).
- **Shared clock, accepted.** Scenarios advance the one simulated clock; the Scenario Lab says
  so in a banner, and each run creates its own customer so checks stay independent.
- `lost_webhook` deliberately leaves its discrepancies open, for the operator to resolve on
  the Reconciliation screen.

## Acceptance criteria

- Fresh clone → setup command → app shows realistic data; each scenario runs from the UI and
  its `expect` steps pass.
