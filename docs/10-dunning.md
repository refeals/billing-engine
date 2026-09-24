# 10 — Dunning

## Goal

The failed-payment sequence from `00-prompt.md` §3: notice on day 0, retry on day 3, access
suspension on day 7, cancellation on day 14. Each step runs once, on the right day, and
stops as soon as the customer pays.

## Depends on

- `07-invoicing-and-payments.md`

## Scope

**In**
- Tables: `dunning_cases`, `dunning_steps`, `customer_notifications`.
- Opening, advancing and closing cases.
- Tick step executing due steps.
- Immediate retry when a new default card is attached during dunning.
- Screen 13, Dunning tab on screen 3, notifications on screen 7.

**Out**
- Real email sending. Notifications are rows in an outbox table.
- Configurable schedules (the schedule is a constant, documented).

## Backend

### Schedule (constant)

| Step | Day | Action |
|---|---|---|
| `day_0_notice` | 0 | notify customer |
| `day_3_retry` | 3 | retry charge + notify |
| `day_7_suspend` | 7 | set `access_suspended_at` + notify (subscription stays `past_due`, decision 1) |
| `day_14_cancel` | 14 | `past_due → canceled` (`dunning_exhausted`), invoice → `uncollectible`, notify |

### Lifecycle
- **Open:** the `invoice.payment_failed` handler opens a case if there's no open case for that
  invoice (unique index on `invoice_id` where `status = 'open'`), and runs `day_0_notice`
  in the same transaction.
- **Advance:** `Ticks::Dunning` finds open cases with `next_step_at <= now` and runs the step.
  The `(dunning_case_id, step)` unique index makes a rerun a no-op.
- **Recover:** the `invoice.paid` handler closes the case as `recovered`, clears
  `access_suspended_at` and transitions `past_due → active`. Any step not yet run is skipped.
- **Retry outcome:** the day 3 retry is only a charge request; the result comes by webhook
  and either recovers the case or leaves it waiting for day 7.
- **Customer cancels during dunning:** case closed as `canceled`.
- **New default card during an open case:** immediate retry, recorded as an extra payment
  attempt linked to the case (not a schedule step, so the schedule continues if it fails).

### Endpoints
From `00-prompt.md` §9, **Dunning**, plus `GET /customers/:id/notifications`.

## Frontend

- Screen 13 **Dunning board**: columns per stage (`day_0`, `day_3`, `day_7 suspended`,
  closed as recovered / exhausted), cards with customer, invoice amount, next step and
  date.
- Screen 3: Dunning tab (steps timeline with outcomes), "Access suspended" banner in the
  header.
- Screen 7: notifications list.

## Tests

- Full sequence: failure on day 0, advance 14 days one by one → steps on days 0, 3, 7, 14
  exactly, subscription `canceled`, invoice `uncollectible`.
- Advance 14 days in one call → same result as day by day.
- Recovery on day 5 → case recovered, no day 7 or 14 steps, subscription `active`.
- Recovery after suspension → access restored.
- New card on day 4 → immediate retry; if it succeeds, case recovered.
- Tick rerun → no duplicate steps or notifications.
- Second failure on the same invoice → same case, no new one.

## Documentation

- README section "Dunning" with the schedule table and a sequence diagram.
- README "Edge cases handled": recovery mid-dunning; recovery after suspension; card updated
  during dunning; job running twice; retry that fails again.

## Acceptance criteria

- With a declining card, advancing the clock shows the case moving across the board and the
  subscription ending `canceled` on day 14; with a card fixed on day 4, it recovers.
