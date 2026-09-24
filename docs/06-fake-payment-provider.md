# 06 — Fake payment provider

## Goal

A fake Stripe that our engine talks to through a gateway interface, and that reports back
only through webhooks, like the real one. Swapping it for real Stripe later should mean
writing one new gateway class.

## Depends on

- `05-webhook-ingestion.md`

## Scope

**In**
- `PaymentGateway` interface and the `FakeStripe` implementation.
- `mocked_webhook_events` (provider outbox) and the dispatcher that delivers it to our inbox.
- Delivery controls: deliver, drop, duplicate, redeliver.
- Simulator event endpoints and a first version of screen 12 (manual events and outbox).

**Out**
- Canned scenarios and reset/reseed (plan 12).
- Invoice and refund calls are defined in the interface here but used in plans 07 and 09.

## Backend

### Boundary
- `PaymentGateway` (module with the interface) and `PaymentGateway.current` returning the
  configured implementation. Methods:
  - `create_customer(customer)` → `cus_…`
  - `attach_payment_method(customer, token)` → `pm_…` plus card details
  - `create_subscription(subscription)` / `update_subscription` / `cancel_subscription`
  - `create_invoice(invoice)` → `in_…`
  - `pay_invoice(invoice, payment_method)` → accepted (the result arrives as a webhook)
  - `refund(payment_attempt, amount_cents)` → `re_…` (result as a webhook)
- Synchronous return values are only identifiers. Outcomes (paid, failed, refunded) always
  arrive as webhooks, so our code can't take a shortcut the real provider won't offer.
- Plans 03 and 04 start calling the gateway here (customer, card, subscription creation).
- Implemented now: `create_customer`, `attach_payment_method`, `create_subscription`,
  `update_subscription`. Invoice, payment and refund calls are added in plans 07 and 09, with
  the features that use them.
- Gateway methods take plain values, never models: the fake can't read our tables even by
  accident (a spec checks every SQL statement a gateway call issues).

### When the engine calls the provider
- **Creates** (customer, card, subscription) call the provider inside our transaction, after
  every local check, because the provider hands out the id we insert. The fake shares our
  database, so its outbox row joins our transaction and delivery happens after commit, when
  our row exists. With the real Stripe the call can't be rolled back and its webhook may even
  arrive before our insert commits; the inbox already covers that (unknown object → failed →
  retried).
- **Updates** to a subscription are pushed from a model `after_commit` with a snapshot of
  plain values, so the provider never hears about something we rolled back and no service can
  forget the sync. Webhook observation uses `update_columns`, which skips the callback, so
  what the provider reports is never echoed back.

### `FakeStripe`
- Lives under `app/models/fake_stripe/` (namespaced, its own tables only). It never reads
  our domain tables: everything it needs comes in the call arguments or from its own outbox.
  This is what makes the outbox a trustworthy "expected" source for reconciliation.
- Payment outcome from the card token (plan 03) and the expiry date against `BillingClock`.
  `pm_card_succeedsAfterFailures_N` counts its own previous failures in the outbox.
- Each call appends Stripe-shaped events to `mocked_webhook_events` (e.g. `pay_invoice` →
  `charge.succeeded` + `invoice.paid`, or `charge.failed` + `invoice.payment_failed`).
- `provider_created_at` from `BillingClock`; outbox `id` breaks ties within a tick.

### `mocked_webhook_events`
- Columns as in `00-prompt.md` §10. `delivery_status`: `pending` / `delivered` / `dropped`.

### Dispatcher
- New events are created `pending`. `FakeStripe::Dispatcher.flush` delivers pending events in
  outbox order by calling `Webhooks::Ingest` in process (same code path as the HTTP endpoint,
  without the network).
- Flush runs **after** the engine's transaction commits (end of request, end of each tick).
  Delivering inside the transaction would let a webhook see uncommitted data and nest
  transactions in a way the real world never does.
- Delivery modes set on emit: `deliver` (default), `drop` (stays `dropped`, never reaches us),
  `copies: N` (delivered N times — duplicates).
- A 500 from the inbox leaves the event `pending` with a retry count; the next flush retries
  it, like a provider retry schedule. `Ticks::RetryProviderDeliveries` (last daily step)
  guarantees at least one retry pass per simulated day.
- The flush is re-entrant safe: a handler that makes the engine emit new events while we are
  delivering gets them delivered in the same flush.

### Endpoints
From `00-prompt.md` §9, **Simulator**: `POST /simulator/events`, `POST /simulator/events/:id/deliver`,
`GET /simulator/events`. Manual event types: `customer.subscription.updated` and
`.deleted`, with an optional `status` so the provider can disagree with the engine.

## Frontend

- Screen 12 **Scenario Lab**, first version:
  - Outbox table (event id, type, delivery status, delivery count) with "Deliver" /
    "Redeliver" actions.
  - Manual event form: type, subscription, delivery mode, copies.
- Link from each outbox row to the matching inbox row (screen 11) when delivered.

## Tests

- `FakeStripe` never touches domain tables (asserted by a query counter / table allowlist in
  tests).
- Card tokens produce the documented outcomes; an expired card fails with `expired_card`
  once the clock passes the expiry month.
- Dispatcher delivers in order, only after commit; `drop` never delivers; `copies: 3` produces
  one processed row and two duplicates in the inbox.
- Inbox 500 → event stays pending and is retried on next flush.

## Documentation

- README "Architecture decisions": gateway boundary, outcomes only via webhooks, fake
  provider as an event-sourced outbox, delivery after commit. Include a Mermaid sequence
  diagram (engine → gateway → outbox → dispatcher → inbox → handler).
- README "Edge cases handled": dropped webhook (caught later by reconciliation); provider
  retry after our 500.

## Acceptance criteria

- From the Scenario Lab, emit an event with `copies: 3` and see one processed and two
  duplicate deliveries in the webhook inbox.
- Emit a dropped event and see it only in the outbox.
