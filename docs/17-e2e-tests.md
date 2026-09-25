# 17 — End-to-end tests

## Goal

Exercise both apps together in a real browser, the way an operator uses them: sign-in and
redirects, the session cookie across origins, dialogs, the clock refreshing every screen,
the Scenario Lab and reconciliation. RSpec (API) and Vitest (web) already cover the rules;
this suite checks that the pieces are wired together.

## Depends on

- `16-demo-login.md` (every screen is behind the login).

## Decisions

1. **Playwright, Chromium only**, in `web/e2e/`. Chromium keeps CI time and the browser
   download small; the app has no browser-specific code.
2. **A real API with its own database.** Playwright starts the API in the `test` environment
   on port 3100 against `storage/e2e.sqlite3` (`TEST_DATABASE` in `config/database.yml`, the
   only API change), and the production build of the web app with `vite preview` on port
   4174. The dev database and RSpec's are never touched. `localhost:4174` and
   `localhost:3100` are the same site, so the session cookie works as in production.
3. **Known state from the seeds.** `e2e/global-setup.ts` signs in through the API, resets
   the demo (seeded data, clock on 2026-03-16) and saves the session cookie; every spec
   starts signed in from it (`auth.spec.ts` starts signed out on purpose).
4. **Serial and self-contained.** One worker: there is one simulated clock. Specs that assert
   seeded figures reset first (`resetDemo`); specs that change data create their own
   customer and subscription (`createSubscription`), so the order doesn't matter.
5. **Accessible selectors** (`getByRole`, `getByLabel`, `getByText`). No `data-testid` was
   added; the one used (`clock-now`) already existed.
6. **The API is started by a script** (`e2e/start-api.sh`) that uses `mise` when installed
   and plain `bin/rails` otherwise (CI), prepares the database, ensures the demo user, and
   clears a stale pid file left by a killed run.

## What is covered

| Spec | Story |
|---|---|
| `auth.spec.ts` | Private URL → login with `?redirect`; wrong password → error; demo credentials → back to the page with its filter; reload keeps the session; sign out → login; private URL redirects again |
| `dashboard.spec.ts` | Seeded figures (MRR $895.17, 3 past due, $177.00 at risk, 0 discrepancies); the Past due tile opens the Dunning board |
| `clock.spec.ts` | +3 days moves the header date and runs a day-3 dunning retry (a case moves from Notified to Retried) |
| `subscription-lifecycle.spec.ts` | Create a customer, add a test card, subscribe, schedule a cancellation, undo it, see it in the audit history |
| `conflict.spec.ts` | Two tabs on one subscription: the stale one gets "changed after you opened it" and reloads |
| `refund.spec.ts` | A $10 card refund appears on the invoice; the form refuses more than what is left |
| `scenario-lab.spec.ts` | Run "Duplicate webhook" (passed, with its checks); run "Lost webhook", redeliver from Reconciliation, and the subscription reconciles to zero |

## Running

```sh
cd web
pnpm exec playwright install chromium   # once
pnpm test:e2e                           # starts the API and the web app, ~35 s
pnpm test:e2e:ui                        # interactive: watch, pick, time-travel through steps
```

A failed test keeps a trace (`test-results/…/trace.zip`, open with
`pnpm exec playwright show-trace <file>`) and a screenshot. In CI they are uploaded as the
`playwright-report` artifact.

## Decisions taken during implementation

- **The demo credentials moved to `src/api/demoCredentials.ts`** (re-exported by
  `session.ts`): a module without imports, so the Node-side setup can use the same values
  as the login screen instead of a third copy.
- **The over-refund check is asserted in the form**, which refuses the amount before calling
  the API; the API's own refusal is covered by RSpec.
- Vitest ignores `e2e/`; ESLint ignores Playwright's output folders; `e2e/**` is
  type-checked with the Node config.
- Two runs in a row pass in about 35 seconds each, and RSpec's database stays empty after a
  run.

## Acceptance criteria

- `pnpm test:e2e` passes from a clean checkout after `pnpm install` and the Chromium
  download, and in the CI `e2e` job.
