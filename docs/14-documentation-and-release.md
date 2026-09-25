# 14 — Documentation and release

## Goal

Finish the public presentation. Each earlier plan updated the README as it went; this plan
reviews the whole thing as a reader who has never seen the project.

## Depends on

- `13-dashboard.md`

## Scope

**In**
- README final pass.
- `docs/architecture.md`.
- Screenshots.
- Code comment pass.
- Final CI and setup check from a clean clone.

**Out**
- Deployment. The project runs locally; a hosted demo is a future improvement.

## Tasks

### README
Final structure:
1. What this is and the problem it solves (short).
2. Screenshots (dashboard, subscription timeline, dunning board, Scenario Lab).
3. Quick start (one setup command, one run command, ports, env vars).
4. "Try it": guided tour through the scenarios (plan 12).
5. Domain: state machine (Mermaid), proration, dunning, reconciliation.
6. Architecture decisions and why (gathered from every plan).
7. **Edge cases handled**: one line each, linking to the scenario and the test.
8. Out of scope and future improvements (from `00-prompt.md` §7, plus: disputes, historical
   metrics, hosted demo, interval changes with proration).
9. Project structure.

### `docs/architecture.md`
- Component diagram (engine, gateway, fake provider, outbox, inbox, handlers, ticks).
- Sequence diagrams: payment, dunning, lost webhook + reconciliation.
- Data model diagram (Mermaid ER) generated from the final schema.

### Code pass
- Comments explain why, not what; remove any "what" comments.
- No dead code or leftover TODOs.
- Every identifier in English (grep for Portuguese words as a last check).

### Release check
- Clean clone → documented setup → seeds → all scenarios pass → CI green.
- Tag `v1.0.0`.

## Decisions taken during implementation

- **README for a first-time reader**: a "What to look at" list up front, screenshots, then
  quick start and the guided tour; architecture decisions grouped (time and consistency,
  money, provider and webhooks, API and frontend); the roadmap became "How it was built".
- **Every edge case links to its spec** (and to the scenario that reproduces it, when there
  is one), grouped by area.
- **Screenshots** are taken with headless Chrome against the seeded demo (no new
  dependency), saved in `docs/screenshots/`.
- **Code pass**: comments that referred to future plans rewritten in the present; the
  sidebar's "ships in plan NN" placeholder removed, since every section exists.
- **Found while taking screenshots**: a recovered dunning case showed $0.00 (amount due after
  payment); the board now shows the invoice total.
- **Release check** runs on a copy of the repository's files without ignored ones (a fresh
  clone of the final state): `bin/setup` seeds the demo, the CI checks pass and all ten
  scenarios pass through the API. The `v1.0.0` tag is created by the maintainer.

## Acceptance criteria

- Someone following only the README can run the project and reproduce every edge case listed.
