# Features

What the billing engine does and what each screen is for, in one page. The
[README](README.md) has the rules in depth; this is the map.

## What it is

The back-office of a fictional SaaS that sells monthly or yearly subscriptions to gyms and
studios. One operator signs in (demo credentials are on the login screen) and manages
customers, subscriptions and money. The payment provider (Stripe) is simulated inside the
app, and a **simulated clock** moves time forward, so weeks of billing happen in seconds.

## Core behavior

- **Subscriptions** follow a strict lifecycle: `trialing → active → past_due / paused →
  canceled`. Only allowed moves happen, each with a reason, and each is recorded.
- **Billing**: a trial is charged when it ends and an active subscription when its period
  ends. Credit balance is spent before the card. Invoices are numbered with no gaps
  (`BE-2026-000123`).
- **Payments are confirmed by the provider**, never assumed: the engine asks for a charge
  and waits for the provider's webhook, which says it was paid or that it failed.
- **Plan changes mid-period are prorated**: an upgrade charges the difference right away, a
  downgrade turns it into credit. What was previewed is exactly what is charged.
- **Failed payments go through dunning**: notice on day 0, retry on day 3, access suspended
  on day 7, canceled on day 14. A payment at any point recovers the subscription.
- **Refunds**: partial or full, up to what was paid, to the card or to the credit balance.
- **Reconciliation** compares the engine with the provider's own history each simulated day
  and flags every difference, with evidence.
- **Audit trail**: every change records who made it (operator, webhook, daily job,
  reconciliation). The history can't be edited or deleted.

## Screens

| Screen | What you see | What you can do |
|---|---|---|
| **Login** | Email and password form, plus the demo credentials | Sign in; "Use demo credentials" fills the form |
| **Header** (every screen) | Simulated date | Advance the clock +1, +3 or +7 days, or reset it; every screen then reloads |
| **Dashboard** | MRR, active and past-due counts, amount at risk, open discrepancies, subscriptions by status, recent activity | Click any tile to open the filtered list; run reconciliation; open the Scenario Lab |
| **Subscriptions** | All subscriptions, filterable by status and customer | Create a subscription |
| **Subscription detail** | Status, plan, current period, card to be charged, invoices, plan changes, dunning status | Cancel now or at period end (and undo), pause (with an optional resume date), resume, change plan with a proration preview (now or at renewal). Only the actions the current status allows are shown |
| **Subscription history** | Every change to it, newest first, with who did it and the before/after values | Read only |
| **Customers** | All customers, searchable | Create a customer |
| **Customer detail** | Cards, credit balance and its ledger, subscriptions, invoices, notifications sent | Add a test card (each one behaves differently: success, declined, expired…), make one the default, adjust credit, subscribe |
| **Plans** | Plans with price, interval and trial days | Create a plan, archive a plan (price and interval can't change after creation) |
| **Invoices** | All invoices, filterable by status | Open one |
| **Invoice detail** | Lines, totals, credit applied, payment attempts, refunds | Retry an open invoice with the current card; refund a paid one |
| **Dunning** | A board of failed payments by stage: notified, retried, suspended, recovered, canceled | Open the subscription behind each case |
| **Reconciliation** | Open differences between the engine and the provider, and past runs | Run now; resolve each difference: redeliver the lost event, reprocess a failed one, apply the provider's value, resend the engine's state, or acknowledge with a note |
| **Webhook inbox** | Every provider event received once, with its outcome (processed, skipped as stale, ignored, failed) and how many duplicate deliveries it had | Open one to see its payload and what it changed; reprocess a failed one |
| **Audit log** | Every recorded change in the system | Filter by type, actor, subscription, customer and date |
| **Scenario Lab** | Ten one-click stories reproducing the hard cases (duplicate webhook, lost webhook, full dunning, upgrade…), recent runs, the provider's outbox | Run a scenario and see each step and check it passed; make the provider send, lose or duplicate an event; reset all demo data |
| **Sign out** (sidebar) | The signed-in email | End the session and return to the login |

## Expected behavior worth knowing

- **Moving time drives everything.** Renewals, trial ends, dunning steps, resumed pauses and
  reconciliation all run when the clock advances, day by day, even on a 7-day jump.
- **Two operators, one subscription**: if it changed since you opened it, your action is
  refused and the screen offers to reload.
- **A double click or a retry never charges twice**, and the same webhook received twice is
  applied once.
- **The demo is shared.** Everyone uses the same data and clock, so things may move between
  two visits. "Reset demo data" in the Scenario Lab restores the seeded state: about 20
  studios with 70 days of history, starting on 2026-01-05.
- **Signed out, nothing is reachable** except the login. An expired session sends you back
  to the login and then to the page you were on.

For how it is built: [docs/architecture.md](docs/architecture.md) and the learning guides,
[LEARN-API.md](LEARN-API.md) and [LEARN-WEB.md](LEARN-WEB.md).
