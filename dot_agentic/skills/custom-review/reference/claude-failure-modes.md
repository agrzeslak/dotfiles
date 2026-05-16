# Claude failure modes

Eleven archetypes of reviews that miss bugs. Read during the Falsification phase and again during the Review-phase preflight. These are not generic anti-patterns — they are the **specific failure modes Codex identified** in Claude reviews on real diffs.

For each, the failed phase is named so the SKILL.md preflight can route a "no" answer back to the correct phase.

---

## 1. Stopped at local correctness

The changed function looks reasonable, so the review ends there. The bug is in a caller, serializer, export path, or alternate UI that still expects the old behavior.

> Typical miss: a field shape changes. The primary page updates. CSV export, admin view, or background job still uses the old field.

**Failed step:** Search phase — trace did not extend past the changed lines, or hit classification did not include dependent roles.

---

## 2. Trusted tests as correctness evidence

Tests are treated as proof rather than another artifact to review. Tests can encode the regression, use fixtures that hide the issue, or assert only the happy path.

> Typical miss: test data uses the same fake ID for `workspaceId` and `organizationId`. A semantic ID mixup passes.

**Failed step:** Tests phase — fixture blindness and assertion correctness were not checked.

---

## 3. Believed the PR description

If the PR says *"no behavior change,"* the reviewer treats the change as a pure refactor. But refactors often change query enablement, cleanup, loading states, memoization, or error rendering.

> Typical miss: extracted child component now fetches on mount because the parent's conditional render was removed.

**Failed step:** Model phase — refactor-claims were not treated as falsifiable claims; Falsification phase — did not target behavioral drift (query enablement, side effects, error rendering, memoization).

---

## 4. Did not enumerate alternate code paths

The review inspects create but not edit, desktop but not mobile, single action but not bulk action, admin but not regular user.

> Typical miss: validation added to create flow but edit flow can still save invalid data.

**Failed step:** Search phase (sibling inspection) — sibling axes were not enumerated.

---

## 5. Skipped error / loading / empty paths

The success path survives the review. The old error or loading behavior disappears.

> Typical miss: failed request now renders "no results," which tells the user a false state and suppresses retry affordance.

**Failed step:** Falsification phase — `failure_parity` sub-check was not addressed.

---

## 6. Did not search producers and consumers

A new enum variant, status, edge type, or permission gets handled in the visible location but not everywhere.

> Typical miss: frontend can display a new status, but server-side filtering excludes it because the query predicate still enumerates the old statuses.

**Failed step:** Search phase — hit classification did not cover both producer and consumer roles, or did not classify hits exhaustively.

---

## 7. Reported suspicions without verification

The opposite failure: the reviewer reports *"possible stale state"* or *"may need cleanup"* without proving a path. This degrades trust and hides real bugs among maybe-comments.

> Typical pattern: review contains 8 findings, of which 5 are hedged with `maybe` / `possibly` / `seems`. The hedged ones are noise.

**Failed step:** Verification phase — main-thread re-read did not drop unverified candidates; Review-phase output rules — hedging language was not stripped.

---

## 8. Missed async invalidation

The reviewer checks that new requests work, but not that old requests are cancelled or ignored when state changes.

> Typical miss: user clears a search. An older request resolves and repopulates stale results.

**Failed step:** Falsification phase — `async_invalidation` sub-check was not addressed, or was filled with `N/A` without justification.

---

## 9. Confused UI gating with authorization

If the button is hidden, the reviewer treats the action as protected. Server-side enforcement still needs to be checked.

> Typical miss: frontend hides delete for non-owners. The backend endpoint accepts any project member.

**Failed step:** Search phase — `ui-render` hits were not differentiated from `permission` hits; Falsification phase — did not separately attack the server-side authorization boundary.

---

## 10. Missed old data and rollout compatibility

The reviewer evaluates new code against ideal new data. Existing rows, old clients, partial deployments, and saved configs are where bugs surface.

> Typical miss: migration assumes every account has at least one event. Production has accounts without events.

**Failed step:** Falsification phase — `backward_compat` sub-check was not addressed.

---

## 11. Overweighted cleanliness

The review spends budget on naming, duplication, or *"consider extracting"* comments. These consume attention that should go to contracts, dependents, and edge paths.

> Typical pattern: review has 12 entries. 9 are style / naming / extraction. 1 actual bug is buried at position 7.

**Failed step:** Review-phase output rules — skip list was not applied; finding minimality rule was not enforced.

---

## Use at the Review-phase preflight

The SKILL.md's eleven-question preflight maps directly to these failure modes:

| Preflight question | Failure mode |
|---|---|
| Q1 (sources of truth) | (none — separate gate) |
| Q2 (extended past local correctness) | 1 |
| Q3 (tests as artifact not proof) | 2 |
| Q4 (refactors as claims) | 3 |
| Q5 (sibling axes) | 4 |
| Q6 (error/loading/empty paths) | 5 |
| Q7 (producers + consumers) | 6 |
| Q8 (dropped unverified) | 7 |
| Q9 (async invalidation) | 8 |
| Q10 (UI gating vs server auth) | 9 |
| Q11 (backward-compatibility) | 10 |
| (no preflight q) | 11 (finding minimality — checked in output assembly) |

If any preflight question is "no," return to the named phase.
