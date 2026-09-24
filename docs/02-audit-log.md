# 02 — Audit log

## Goal

An append-only audit trail that every later feature writes to. It comes early because
retrofitting auditing onto existing code is where gaps appear.

## Depends on

- `01-foundation.md`

## Scope

**In**
- `billing_events` table and model.
- The reusable append-only mechanism (model concern + SQLite triggers).
- `Audit.record` API used by every service from now on.
- Global audit endpoint and screen.

**Out**
- Per-subscription timeline (plan 04, once subscriptions exist).
- Hash chain (future improvement, `00-prompt.md` §7).

## Backend

### Append-only mechanism
- `AppendOnly` model concern: `readonly?` returns true once persisted, and `destroy` /
  `delete` raise.
- Migration helper `create_append_only_triggers(table)` that creates
  `BEFORE UPDATE` and `BEFORE DELETE` triggers with `RAISE(ABORT, '<table> is append-only')`.
  The model layer can be bypassed (`update_column`, raw SQL); the database can't.
- `schema.rb` doesn't keep triggers, so switch to `config.active_record.schema_format = :sql`
  (`structure.sql`). Note this in the README, since it's an unusual choice.

### Table `billing_events`
- `subscription_id` (nullable, no FK yet — added in plan 04), `customer_id` (nullable, FK in
  plan 03)
- `event_type` (string, indexed)
- `actor_type`: `webhook` / `admin` / `system_job` / `reconciliation`
- `webhook_event_id` (nullable, FK added in plan 05)
- `data` (json: `before`, `after`, plus free context)
- `occurred_at` (simulated time, from `BillingClock`), `created_at` (real time)
- Indexes: (`subscription_id`, `occurred_at`), (`customer_id`, `occurred_at`), `event_type`.

Keeping both `occurred_at` and `created_at` is deliberate: one is business time, the other is
when the row was really written. The difference is useful when debugging the simulator.

### `Audit.record`
- `Audit.record(event_type:, actor:, subject:, before: nil, after: nil, context: {})`.
- Must run inside the caller's transaction. If the business change rolls back, the audit row
  rolls back too, and vice versa. The service raises if called outside a transaction, so a
  forgotten wrapper fails in tests instead of silently writing half a story.
- The current actor (`admin`, `webhook`, …) comes from `Current.actor`, set by the
  controller, webhook ingestor or tick. Services don't pass it around.

### Endpoint
- `GET /api/v1/billing_events?subscription_id=&customer_id=&type=&source=&from=&to=&page=`
- Cursor or page-based pagination (page size 50), newest first.

## Frontend

- Screen 15 **Global audit log** (`/audit`): table with occurred_at, event type, actor,
  subject link, expandable JSON diff. Filters: type, source, date range.
- Shared `AuditEventItem` component (reused by the subscription timeline in plan 04).
- Shared `JsonDiff` component showing `before` / `after`.

## Tests

- Model: update and destroy raise; `update_column` and raw `UPDATE` / `DELETE` SQL fail at
  the trigger level.
- `Audit.record` raises outside a transaction; rolls back with the caller.
- Endpoint filters and pagination.

## Documentation

- README "Architecture decisions": why append-only is enforced in the database and not only
  in Ruby; why `structure.sql`.
- README "Edge cases handled": attempt to update or delete an audit row.

## Acceptance criteria

- Any attempt to modify or delete a `billing_events` row fails, whatever the path.
- The audit screen lists events with working filters (tested with seeded rows).
