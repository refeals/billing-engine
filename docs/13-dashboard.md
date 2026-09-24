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

## Acceptance criteria

- Running `full_dunning` and advancing the clock visibly changes the past-due tile and MRR.
