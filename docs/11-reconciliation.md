# 11 — Reconciliation

## Goal

Compare what our engine believes with what the provider's event history says should be true,
and flag every difference. It's the safety net for everything the previous plans can't
prevent: dropped webhooks, failed handlers, bugs.

## Depends on

- `10-dunning.md` (needs all event types in place)

## Scope

**In**
- Tables: `reconciliation_runs`, `reconciliation_discrepancies`.
- Expected-state projection from the provider outbox.
- Comparator, run service, resolution actions.
- Screen 14; discrepancy count on the subscription detail.

**Out**
- Automatic resolution. Every correction is an explicit operator action.

## Backend

### Projection (`Reconciliation::ProjectExpectedState`, pure)
- Input: every `mocked_webhook_events` row for one subscription, ordered by
  `provider_created_at`, then `id`. Includes events that were dropped or never processed; that's
  the point.
- Output: expected subscription status, plan, current period, and per invoice: status and
  amounts.
- Pure function over events → easy to unit test with hand-written event lists.

### Comparison
- Discrepancy kinds as in `00-prompt.md` §10:
  - `status_mismatch`, `plan_mismatch`, `period_mismatch`
  - `missing_invoice`, `invoice_status_mismatch`, `invoice_amount_mismatch`
  - `undelivered_event` (outbox event `dropped` or still `pending`)
  - `failed_event` (inbox row `failed`)
- Each discrepancy stores `internal_value`, `expected_value` and the ids of the events that
  prove it.
- Flags our engine owns and the provider doesn't know about (e.g. `access_suspended_at`) are
  not compared.

### Runs
- `POST /reconciliation_runs` (all or one subscription), synchronous, since the dataset is small.
- `Ticks::Reconcile` runs a full reconciliation once per simulated day, after all other steps.
- A discrepancy already open for the same subscription, kind and field isn't duplicated; the
  new run references it.

### Resolution
- `apply_expected`:
  - Status: goes through `Subscriptions::Transition` with reason
    `reconciliation_correction`, source `reconciliation`. If the edge isn't allowed by the
    state machine, it's refused and the operator has to acknowledge instead. Reconciliation
    never bypasses the state machine.
  - Undelivered or failed event: redelivers / reprocesses it through the normal inbox.
    Preferred over patching state directly, because the handler applies every side effect
    (invoice, dunning, audit) correctly.
- `acknowledge`: requires a note; state unchanged.
- Both audited as `discrepancy.resolved`.

### Decisions taken during implementation
- **The provider's payment rule** is part of the projection: a paid invoice makes a
  `past_due`/`trialing` subscription `active`, a failed payment makes `active`/`trialing`
  `past_due`; otherwise the last subscription snapshot rules.
- **Engine-owned facts aren't compared** (`access_suspended_at`, `uncollectible`: invoices
  compare paid vs unpaid; card refunds only).
- **A subscription with events still in flight is skipped** for that run (its known
  discrepancies are left as they are): mid-conversation, engine and provider always differ.
- **The daily run happens after the day commits** (`after_all_transactions_commit`), once the
  engine has pushed its changes and the provider's events have been delivered. Inside the
  day's transaction it found differences that vanished a moment later.
- **The inbox decides what was received**: an event the inbox processed isn't "undelivered"
  just because the provider still has it pending for a retry.
- **Resolutions per kind:** `redeliver`, `reprocess`, `apply_expected` (state machine,
  refusable), `resync_provider` (the engine is the authority), `acknowledge` (note
  required). A discrepancy no longer detected becomes `cleared`; an acknowledged one isn't
  reported again unless its values change.
- **`apply_expected` waits for the root cause:** it's blocked while a lost or failed event for
  the same subscription is open, since redelivering the event fixes invoice, dunning and
  status together. Dunning also closes its case by itself if the subscription left
  `past_due` without a payment.
- **A failing daily check never stops the clock**: the error is reported and the next day's
  run tries again.

## Frontend

- Screen 14 **Reconciliation**: runs list with "Run now"; run detail with discrepancies
  grouped by subscription; per row: kind, field, internal vs expected, evidence event links,
  "Apply expected" (disabled with a reason when not possible) and "Acknowledge" (note
  required).
- Screen 3: badge with the open discrepancy count, linking to the filtered list.

## Tests

- Projection unit tests from hand-written event lists.
- Drop an `invoice.paid` → run flags `undelivered_event` + `invoice_status_mismatch` +
  `status_mismatch`; "apply expected" redelivers and the next run is clean.
- Failed handler → `failed_event`; resolved by reprocess.
- Impossible correction (e.g. expected `active` while internal is `canceled`) → refused,
  acknowledgement works.
- Consistent system → zero discrepancies (run against the full seed data).
- Repeated runs don't duplicate open discrepancies.

## Documentation

- README section "Reconciliation": how expected state is derived, why corrections go through
  the inbox or the state machine.
- README "Edge cases handled": lost webhook; handler failure never retried; impossible
  correction.

## Acceptance criteria

- Drop an event in the Scenario Lab, run reconciliation, see the discrepancy with its
  evidence, apply expected, run again and get zero discrepancies.
