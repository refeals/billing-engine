# 09 — Refunds

## Goal

Full and partial refunds on paid invoices, to the original card or to the customer's credit
balance, without ever refunding more than was paid.

## Depends on

- `08-plan-changes-and-proration.md` (uses the credit ledger flows)

## Scope

**In**
- `refunds` table.
- Refund to original method (through the gateway, confirmed by webhook) and to credit
  balance (internal).
- `charge.refunded` / `refund.updated` handlers.
- Refund section on the invoice detail screen.

**Out**
- Disputes / chargebacks (listed as a future improvement in the README).

## Backend

### `refunds`
- Columns as in `00-prompt.md` §10. `status`: `pending` / `succeeded` / `failed`.

### Flow
- `Refunds::Create(invoice, amount_cents, destination:, reason:)`:
  - Locks the invoice row and checks `amount_cents <= amount_paid_cents - refunded_or_pending`.
    Pending refunds count against the limit, so two quick requests can't both pass.
  - `original_method`: creates a `pending` refund, calls `gateway.refund`; the webhook moves
    it to `succeeded` (or `failed`, releasing the amount) and updates
    `invoices.amount_refunded_cents`.
  - `credit_balance`: `succeeded` immediately plus a ledger credit (`refund_to_balance`),
    same transaction. No provider call, since no money leaves.
- Only `paid` invoices are refundable. Refunds don't change the subscription state; a full
  refund doesn't cancel anything. Canceling is a separate, explicit action.
- Audited as `refund.requested`, `refund.succeeded`, `refund.failed`.

### Endpoint
`POST /invoices/:id/refunds` as in `00-prompt.md` §9.

### Decisions taken during implementation
- **Refundable = card payment minus pending and succeeded refunds.** Credit applied to an
  invoice isn't cash, so it isn't refundable; a failed refund releases its amount.
- **The limit holds in three places:** the service (under an invoice lock), a database check
  on `invoices.amount_refunded_cents <= amount_paid_cents`, and the fake provider, which
  refuses to refund more than it charged (from its own outbox).
- **Only `pending → succeeded/failed` changes amounts**, so a duplicate or late
  `refund.updated` can't count twice. `charge.refunded` is compared (audited with `matches`),
  not applied.
- **Test card `pm_card_refundFail`**: charges succeed, refunds fail, like Stripe's
  refund-failure test card.
- **Refunds never change the subscription.**

## Frontend

- Screen 10: refunds table and "Refund" dialog (amount prefilled with the refundable
  remainder, destination, reason). The refundable remainder is shown and enforced in the form,
  and the API is still the source of truth.

## Tests

- Partial refund, then another partial up to the exact paid amount; one cent more → 422.
- Pending refunds count against the limit.
- Failed refund webhook releases the amount.
- Refund to balance creates a ledger entry and no gateway call.
- Refund on an open invoice → 422.
- Duplicate `charge.refunded` → no double-count.

## Documentation

- README "Edge cases handled": partial refund; over-refund attempt; concurrent refunds;
  refund to credit balance.

## Acceptance criteria

- On a paid invoice, a partial refund shows up as pending, then succeeded after the webhook,
  with the refundable remainder updated.
