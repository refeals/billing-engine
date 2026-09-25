# Architecture

How the pieces of the billing engine fit together. The [README](../README.md) explains the
domain rules; this page shows the components, the three flows that matter most and the data
model. Every diagram reflects the code as it is at `v1.0.0`.

## Components

```mermaid
flowchart LR
    Web["Vue app<br/>(operator screens, Scenario Lab)"] -->|JSON + Idempotency-Key| API["API controllers<br/>api/v1"]
    API --> Services["Domain services<br/>subscriptions, invoices, plan_changes,<br/>refunds, dunning, reconciliation"]
    Services --> Audit["Audit.record<br/>billing_events (append-only)"]
    Services --> Gateway["PaymentGateway"]
    Gateway --> Fake["FakeStripe::Gateway<br/>+ Charges (test-card outcomes)"]
    Fake --> Outbox[("Provider outbox<br/>mocked_webhook_events")]
    Outbox -->|after commit| Dispatcher["FakeStripe::Dispatcher"]
    Dispatcher --> Ingest["Webhooks::Ingest<br/>inbox: webhook_events"]
    HTTP["POST /webhooks/stripe"] --> Ingest
    Ingest --> Process["Webhooks::ProcessEvent"]
    Process --> Handlers["Handlers (Registry)<br/>invoice.paid, invoice.payment_failed,<br/>charge.*, refund.updated, customer.subscription.*"]
    Handlers --> Services
    Clock["BillingClock.advance!"] --> Ticks["Ticks::Run, one day at a time"]
    Ticks --> Services
    Recon["Reconciliation::Run"] -->|replays| Outbox
    Recon -->|compares with| Services
```

- **The engine never waits for the provider.** Gateway calls return identifiers only; every
  outcome (paid, failed, refunded) comes back as a webhook through the same inbox a real
  Stripe would use.
- **The fake provider never reads engine tables.** It keeps its own history in the outbox,
  which is why reconciliation can treat that history as an independent "expected state".
- **Time is simulated.** `BillingClock.now` is the only clock (a RuboCop cop forbids
  `Time.current`). Advancing N days runs N ticks, each in its own transaction.

### The daily tick

`Ticks::Run::STEPS`, in this order, because each step depends on the one before:

| Step | What it does |
|---|---|
| `CancelAtPeriodEnd` | cancels subscriptions whose period ended with a cancellation scheduled |
| `EndTrials` | issues the trial-end invoice and asks the provider to collect it |
| `ResumePaused` | ends timed pauses, starting a fresh period |
| `Renew` | rolls the period, applies a scheduled plan change, issues and collects the invoice |
| `RunDunningSteps` | runs every dunning step due today (notice, retry, suspend, cancel) |
| `RetryProviderDeliveries` | sends again the provider events still pending (the inbox failed them earlier) |
| `Reconcile` | full reconciliation, **after** the day's transaction has committed and its events were delivered, so in-flight changes aren't reported as differences |

## Flows

### A renewal paid by card

```mermaid
sequenceDiagram
    participant Tick as Tick (Renew)
    participant Engine as Invoices::Issue / RequestPayment
    participant Gateway as FakeStripe
    participant Outbox
    participant Inbox as Webhooks::Ingest
    participant Handler as InvoicePaid handler
    Tick->>Engine: period ended
    Engine->>Engine: roll period, issue invoice (credit spent first), audit
    Engine->>Gateway: pay_invoice(provider_invoice_id)
    Gateway->>Outbox: charge.succeeded, invoice.paid (pending)
    Gateway-->>Engine: charge id
    Note over Engine,Outbox: day's transaction commits
    Outbox->>Inbox: deliver (Dispatcher, oldest first)
    Inbox->>Inbox: INSERT … ON CONFLICT (claim), lock + re-read
    Inbox->>Handler: process once
    Handler->>Handler: payment attempt, invoice paid, past_due → active, audit (actor webhook)
```

### Dunning, day 0 to day 14

```mermaid
sequenceDiagram
    participant Inbox as invoice.payment_failed
    participant Dunning as Dunning services
    participant Tick as Tick (RunDunningSteps)
    participant Provider as FakeStripe
    Inbox->>Dunning: Dunning::Open
    Dunning->>Dunning: subscription past_due, case opened, day-0 notice (same transaction)
    Tick->>Dunning: day 3: RunStep retry
    Dunning->>Provider: pay_invoice (metadata: dunning case and step)
    Provider-->>Inbox: invoice.payment_failed again, same case continues
    Tick->>Dunning: day 7: suspend access
    alt payment arrives (card updated, retry succeeds)
        Provider-->>Inbox: invoice.paid
        Inbox->>Dunning: Dunning::Recover: case recovered, access restored, active
    else nothing by day 14
        Tick->>Dunning: day 14: cancel subscription, invoice uncollectible, case exhausted
    end
```

Each step writes a `dunning_steps` row (unique per case and step), so a job running twice or
a clock jumping two weeks still runs each step exactly once.

### A lost webhook, found and fixed

```mermaid
sequenceDiagram
    participant Provider as FakeStripe outbox
    participant Engine
    participant Recon as Reconciliation::Run
    participant Operator
    Provider->>Provider: invoice.paid emitted as dropped (never delivered)
    Note over Engine: invoice still open, subscription past_due
    Recon->>Provider: replay the subscription's events (ProjectExpectedState)
    Recon->>Engine: compare status, plan, period, invoices, deliveries
    Recon->>Recon: open discrepancies with evidence event ids:<br/>undelivered_event, invoice_status_mismatch, status_mismatch
    Operator->>Recon: resolve undelivered_event: redeliver
    Recon->>Engine: deliver through the normal inbox (every side effect runs)
    Recon->>Recon: next run clears the invoice and status differences
```

A status correction (`apply_expected`) is blocked while the lost event behind it is still open,
because redelivering fixes the invoice, the dunning case and the audit trail together;
patching the status alone would fix only the symptom.

## Rules that hold everywhere

- **One transaction per business change**, and its audit row inside it (`Audit.record`
  raises without a joinable transaction).
- **Provider events are delivered after every transaction has committed** (`after_all_transactions_commit`),
  so a webhook never acts on data that might roll back, and the provider never hears about
  a change that did.
- **Optimistic locking** on subscriptions (`lock_version`): a stale screen gets 409.
- **Idempotency keys** on every state-changing request from the UI; the webhook inbox is
  idempotent by provider event id.
- **Append-only tables** are protected twice: the `AppendOnly` model concern and SQLite
  triggers (`*_no_update`, `*_no_delete`) kept in `db/structure.sql`.

## Data model

Append-only (triggers refuse `UPDATE` and `DELETE`): `billing_events`,
`subscription_state_transitions`, `credit_ledger_entries`, `invoice_line_items`,
`payment_attempts`, `dunning_steps`, `customer_notifications`. Migrations never add a
foreign key to them, or pointing at them, after they are created: SQLite adds constraints by
rebuilding the table, and the rebuild would silently drop its triggers.

```mermaid
erDiagram
    customers ||--o{ payment_methods : has
    customers ||--o{ subscriptions : has
    customers ||--o{ credit_ledger_entries : "credit moves"
    customers ||--o{ customer_notifications : receives
    plans ||--o{ subscriptions : "priced by"
    subscriptions ||--o{ subscription_state_transitions : "status history"
    subscriptions ||--o{ invoices : bills
    subscriptions ||--o{ plan_changes : has
    subscriptions ||--o{ dunning_cases : has
    subscriptions ||--o{ reconciliation_discrepancies : "flagged in"
    invoices ||--o{ invoice_line_items : lines
    invoices ||--o{ payment_attempts : "charged by"
    invoices ||--o{ refunds : "refunded by"
    invoices ||--o| dunning_cases : "unpaid in"
    dunning_cases ||--o{ dunning_steps : runs
    reconciliation_runs ||--o{ reconciliation_discrepancies : finds
    webhook_events ||--o{ billing_events : causes

    customers {
        int id PK
        string email UK
        string provider_customer_id
        int credit_balance_cents "cache of the ledger"
    }
    plans {
        int id PK
        string code UK
        int amount_cents "immutable"
        string interval "month | year"
        int trial_days
    }
    subscriptions {
        int id PK
        int customer_id FK
        int plan_id FK
        string status "state machine"
        datetime current_period_end
        bool cancel_at_period_end
        int lock_version
    }
    invoices {
        int id PK
        int subscription_id FK
        string number UK "BE-YYYY-NNNNNN"
        string status "open | paid | uncollectible"
        int total_cents
        int amount_due_cents
        int amount_refunded_cents
    }
    plan_changes {
        int id PK
        int subscription_id FK
        string kind "upgrade | downgrade"
        int net_cents
    }
    refunds {
        int id PK
        int invoice_id FK
        string destination "original_method | credit_balance"
        string status
    }
    dunning_cases {
        int id PK
        int invoice_id FK
        string status "open | recovered | exhausted | canceled"
        string next_step
    }
    webhook_events {
        int id PK
        string provider_event_id UK
        string processing_status
        int duplicate_deliveries_count
    }
    billing_events {
        int id PK
        string event_type
        string actor_type
        json data "before / after"
        datetime occurred_at "simulated time"
    }
    reconciliation_discrepancies {
        int id PK
        string kind
        string internal_value
        string expected_value
        json evidence_event_ids
    }
```

Tables outside the diagram: `mocked_webhook_events` (the fake provider's outbox, deliberately
unrelated to engine tables), `idempotency_keys`, `invoice_number_sequences`,
`simulation_clock` (one row), `scenario_runs` (Scenario Lab history).
