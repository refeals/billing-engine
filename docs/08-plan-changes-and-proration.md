# 08 — Plan changes and proration

## Goal

Changing plans mid-cycle with correct proration: upgrades charge the difference now,
downgrades turn the difference into credit, and what the customer is charged is exactly what
the preview showed.

## Depends on

- `07-invoicing-and-payments.md`

## Scope

**In**
- `plan_changes` table.
- Proration calculator, preview and apply.
- Immediate and `at_period_end` strategies (decision 3 in `00-prompt.md`).
- Tick step applying scheduled changes at renewal.
- Change plan modal and Plan changes tab.

**Out**
- Quantity/seat changes, coupons.

## Backend

### Calculator (`Proration::Calculate`, pure function)
- Inputs: old plan amount, new plan amount, period start, period end, proration date.
- `remaining_ratio = (period_end - proration_date) / (period_end - period_start)`, in seconds,
  as a `Rational`, so no float error builds up.
- `credit = -round(old_amount × ratio)`, `charge = round(new_amount × ratio)`, each rounded to
  cents half-up on its own line; `net = credit + charge`. Rounding per line means the
  invoice lines always add up to the total shown.
- Changing interval (monthly ↔ yearly) is out of scope for proration: rejected with 422 in
  this version. Documented as a limitation.

### Preview and apply
- `POST /subscriptions/:id/plan_change_preview` returns the calculation and the
  `proration_date` it used (simulated now).
- `POST /subscriptions/:id/plan_changes` receives that `proration_date` back and recomputes
  with it, so a clock advance between preview and confirm doesn't change the amount silently.
  A `proration_date` outside the current period → 409 `stale_preview`.
- **Upgrade (net > 0), always immediate:** swap plan, invoice with `proration_credit` and
  `proration_charge` lines (`billing_reason: subscription_update`), charge it. The billing
  anchor doesn't move.
- **Downgrade (net < 0), immediate:** swap plan, credit ledger entry for `|net|`
  (`downgrade_proration`), no invoice. The credit is consumed by the next invoice (plan 07
  `credit_applied`).
- **`at_period_end`:** `plan_change` with `status: scheduled`; `Ticks::Renew` applies it
  before generating the renewal invoice. Only one scheduled change per subscription; a new
  one replaces it (the old one becomes `canceled`, audited).
- Each change writes `plan.changed` to the audit log and notifies the gateway
  (`update_subscription`).

### Rules
- Allowed only for `active` subscriptions. `past_due` → 422 (pay first); `paused` and
  `canceled` → 422.
- During `trialing`: plan swap with no proration (nothing has been charged yet).
- Same plan or archived target plan → 422.
- Multiple changes in one cycle work because each one prorates from the plan in effect at
  that moment.
- Upgrade payment fails → plan stays changed, subscription goes `past_due` like any failed
  invoice. Documented choice: reverting the plan would need its own compensation logic and
  Stripe's default behaves the same way.

## Frontend

- Screen 5 **Change plan** modal: plan select, strategy radio (immediate disabled with a
  note when not applicable), preview table (credit, charge, net, credit to balance, due now),
  confirm with an idempotency key.
- Screen 3: Plan changes tab (history plus the scheduled change, with a cancel action).
- Screen 7: credit balance updates after a downgrade.

## Tests

- Calculator: table-driven cases including day 0, last day, exact half, odd cents; lines
  always sum to net.
- Upgrade creates an invoice with two proration lines and charges it.
- Downgrade creates credit, no invoice; next renewal consumes it.
- Preview then clock advance then confirm with the old `proration_date` → same amount; outside
  the period → 409.
- Scheduled change applied at renewal; replaced scheduled change is canceled.
- Past due / paused / trial rules.

## Documentation

- README section "Proration" with the formula and a worked example.
- README "Edge cases handled": downgrade with credit; upgrade with failed payment; two
  changes in the same cycle; clock moves between preview and confirm; plan change during
  trial.

## Acceptance criteria

- Mid-cycle upgrade shows the preview and the resulting invoice matches it to the cent.
- Mid-cycle downgrade grants credit that the next renewal invoice consumes.
