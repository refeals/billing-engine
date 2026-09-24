# 05 — Webhook ingestion and idempotency

## Goal

A webhook inbox that processes each provider event exactly once, handles retries and
out-of-order delivery, and is ready to receive real Stripe events later without changes.

## Depends on

- `04-subscription-state-machine.md`

## Scope

**In**
- `webhook_events` table (the inbox).
- `POST /api/v1/webhooks/stripe` and the `Webhooks::Ingest` service behind it.
- Handler registry and dispatch; stale-event detection.
- Signature verification interface (no-op implementation).
- Inbox endpoints and screen 11.

**Out**
- The fake provider that emits events (plan 06). This plan is tested with JSON fixtures of
  Stripe-shaped payloads under `spec/fixtures/webhooks/`.
- Invoice and charge handlers (plans 07 and 09). This plan ships the `customer.subscription.*`
  handlers.

## Backend

### `webhook_events`
- Columns as in `00-prompt.md` §10.
- FK from `billing_events.webhook_event_id` and `subscription_state_transitions.webhook_event_id`
  added here.

### Ingestion flow (`Webhooks::Ingest`)
1. `SignatureVerifier.verify!(raw_body, headers)` — interface with a `NullSignatureVerifier`
   today. The real one (Stripe) is a future improvement.
2. **Claim** (own transaction): insert the row with `processing_status: processing` using
   `INSERT … ON CONFLICT(provider_event_id) DO NOTHING`.
   - Inserted → go to step 3.
   - Not inserted, existing row `processed` / `skipped_stale` / `ignored_unhandled` →
     increment `duplicate_deliveries_count`, audit `webhook.duplicate_received`, return
     `duplicate`.
   - Not inserted, existing row `failed` → this is a provider retry, not a duplicate: go to
     step 3 with the existing row.
3. **Process** (second transaction): run the handler and mark the row `processed` in the same
   transaction, so the side effects and the "done" mark commit together or not at all.
4. On handler exception: mark `failed` with `last_error` and `attempts + 1` in a separate
   transaction, respond **500**. A non-2xx response is what makes the provider retry.

Why two transactions: if claim and processing shared one, a failing handler would roll back
the inbox row too, and we'd lose the record of the failure.

SQLite has a single writer, so two concurrent deliveries of the same event are serialized;
the unique index is still the real guarantee and is what the tests assert.

### Stale events
- Each handler knows which local record the event is about (subscription, invoice, …).
  That record stores `last_provider_event_at`.
- If `provider_created_at < record.last_provider_event_at` → `skipped_stale`, audited, no
  side effects. Equal timestamps are processed (ties are common because many events share one
  simulated tick; the fake provider guarantees ordering within a tick).
- Ordering is per object, not per subscription: an old `invoice.payment_failed` for invoice A
  must not be discarded because invoice B had a newer event.

### Handler registry
- `Webhooks::Handlers` maps `event_type` → handler class. Unknown types →
  `ignored_unhandled` (200, so the provider doesn't retry forever).
- Handlers run with `Current.actor = webhook` and pass the `webhook_event` to
  `Subscriptions::Transition` and `Audit.record`, so every change is traceable back to the
  event that caused it.
- `customer.subscription.created/updated/deleted`: our engine is the authority on
  subscription state, so these handlers record the provider's view
  (`last_provider_event_at`, audit `provider.subscription_observed`) and don't transition.
  Disagreements are reconciliation's job (plan 11).

### Endpoints
From `00-prompt.md` §9, **Webhooks**. `reprocess` runs step 3 for `failed` rows only;
anything else → 422 `already_processed`.

## Frontend

- Screen 11 **Webhook inbox**: list with status filter, duplicate count badge, error column;
  detail drawer with payload JSON and linked billing events; "Reprocess" button on failed
  rows.

## Tests

- Same payload delivered twice → one row, one side effect, `duplicate_deliveries_count = 1`,
  both responses 200.
- Handler raises → row `failed`, response 500; redelivery processes it; manual reprocess
  works only on failed rows.
- Older event after newer one for the same object → `skipped_stale`, no side effect.
- Older event for a *different* object is still processed.
- Unknown type → `ignored_unhandled`, 200.
- Handler side effects and the `processed` mark commit atomically.

## Documentation

- README "Architecture decisions": inbox pattern, two-transaction flow, why duplicates get
  200 and failures get 500.
- README "Edge cases handled": duplicate webhook; webhook that fails and is retried;
  out-of-order events; unknown event types.

## Acceptance criteria

- Posting the same fixture twice with `curl` shows one processed row and a duplicate count
  of 1 in the inbox screen.
