# 13 — Dashboard

## Goal

A home screen that summarizes billing health and points to where attention is needed.

## Depends on

- `12-scenario-lab-and-seeds.md` (needs realistic data to be designed against)

## Scope

**In**
- `GET /api/v1/dashboard/summary`.
- Screen 1.

**Out**
- Historical charts (MRR over time, churn). Listed as a future improvement.

## Backend

- `Dashboard::Summary` returns:
  - Subscription count per status.
  - MRR: sum of monthly-normalized plan amounts (yearly ÷ 12, integer cents, rounded per
    subscription) for `active` and `past_due` subscriptions. `trialing`, `paused` and
    `canceled` are excluded. The definition goes into the README, since MRR definitions vary.
  - Open dunning cases (count and amount at risk).
  - Open reconciliation discrepancies.
  - Last 10 billing events.
- Plain aggregate queries; no caching needed at this size.

## Frontend

- Screen 1 **Dashboard**:
  - Stat tiles: MRR, active, past due (with amount at risk), open discrepancies.
  - Status breakdown.
  - Recent events list (reusing `AuditEventItem`).
  - Shortcuts: Scenario Lab, Run reconciliation.
  - Tiles link to the filtered lists.
- Refreshes after a clock advance.

## Tests

- MRR with mixed monthly and yearly plans and every status.
- Counts match the seed data.

## Documentation

- README: MRR definition.

## Decisions taken during implementation

- **MRR**: `active` + `past_due` at the current plan's price; yearly ÷ 12 rounded half-up
  per subscription (two $590/yr subscriptions = 2 × $49.17, not $98.33). Cancel-at-period-end
  included; trialing, paused and canceled excluded; scheduled changes count once applied;
  credit and refunds don't reduce it.
- **Amount at risk** sums every open invoice of the subscriptions with an open dunning case,
  not only the invoice that opened the case: a subscription keeps one case while a second
  invoice (an upgrade's proration) can fail too.
- Every status is present in `subscriptions_by_status`, zero-filled, so the UI never guesses.
- The endpoint is a regular admin endpoint (not simulator-only). Plain queries, no cache.
- The seeded demo gives MRR $895.17 from 15 paying subscriptions, asserted in the seed spec.
- The MRR tile links to the unfiltered subscription list, since MRR spans two statuses.

## Acceptance criteria

- Running `full_dunning` and advancing the clock visibly changes the past-due tile and MRR.
