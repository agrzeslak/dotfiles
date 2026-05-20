# Claude failure modes

Fourteen archetypes of Claude reviews missing bugs. Read at workflow step 7 — for each candidate about to promote, run down the table and ask whether the candidate is immune to each mode. If one or two feel load-bearing, return to the named workflow step before promoting.

## The table

| # | Mode | Failed step | Single-line cue |
|---|---|---|---|
| 1 | Stopped at local correctness | 5 (search sideways) | Changed function looks reasonable; bug is in a caller/serializer/export/admin path. |
| 2 | Trusted tests as correctness evidence | 6 (read tests) | Tests pass because the fixture made the regression impossible to fail. |
| 3 | Believed the PR description | 3 (claims) + 5 (sideways) | "No behavior change" treated as proof; refactor-claim was not falsified. |
| 4 | Did not enumerate alternate code paths | 5 (sibling axes) | Reviewed create but not edit; admin but not user; single but not bulk. |
| 5 | Skipped error / loading / empty paths | 5 (failure-state parity) | Refactor preserves success rendering, drops the error branch. |
| 6 | Did not search producers and consumers | 5 (search sideways) | New enum variant/status/edge type handled in the visible site, missed by sibling producer/consumer. |
| 7 | Reported suspicions without verification | 7 (finding-promotion) | "Possible stale state" / "may need cleanup" in a finding — should be Open Question or dropped. |
| 8 | Missed async invalidation | 5 (async invalidation) | New requests work, but old requests aren't cancelled on state change. |
| 9 | Confused UI gating with authorization | 5 (UI vs server) + 7 (promotion) | Button is hidden, action treated as protected, server still accepts the call. |
| 10 | Missed old data / rollout compatibility | 5 (backward-compat) | Migration / new branch evaluated only against ideal new data. |
| 11 | Overweighted cleanliness | 8 (output) | Review has 12 entries; 9 are style/naming/extraction; the real bug is buried. |
| 12 | Read the diff as self-contained (v2) | 3 (claims) + 7 (producer-claim shape) | Producer looks correct; the actual read site reads `Default::default()` / fallback / stale cache. |
| 13 | Trigger-shy on claim-vs-reality (v2) | 7 (claim-vs-reality finding-shape) | Reviewer notices a comment lying; drops because "headline bug isn't reachable through it." |
| 14 | Render-lifecycle elided (v2) | 7 (visibility finding-shape) | "Modal renders under editor" without proving the alt-screen suspend/restore actually re-renders. |

## Detailed examples — the modes that drove the v2 design changes

Modes 12, 13, and 14 are the v2-specific gates encoded as finding-promotion rules in `SKILL.md`. The table is enough for modes 1–11 (they were Codex's enumeration; their fix is embedded in the workflow steps). The three v2 modes deserve a fuller treatment because they fire across PRs the reviewer has seen many times.

### 12. Read the diff as self-contained

The reviewer treats the changed files as the universe of the review. For a new producer (writer, dispatch arm, editor, settings store), the question *"what does the consumer actually read at the effect site?"* is never asked. The producer looks correct in isolation. The consumer either defaults to an unrelated source of truth, is itself unwired, or reads through a dead code path.

> R10 P1: a new editor writes `config.toml`. `Ctrl+g` saves successfully. The engine command that should read the new file resolves against `AgentPermissionsConfig::default()` instead. The feature ships dead. The diff looked self-contained; the dead-wired consumer was outside the changed files.

Other instances: R2 P2, R6 assemble-invariant, R7 TUI rollback. Codex catches this class uniquely (4 of its 7 highest-leverage finds across R1/R2/R6/R7/R10). The v2 producer-claim finding-shape forces the question. The trap is a named consumer that reads `Default::default()` or an unrelated config — a named consumer that doesn't actually read the produced value is theater. Deliberately search: `Default`, `default()`, `unwrap_or_default`, fallback constructors, old config paths, old enum arms.

### 13. Trigger-shy on claim-vs-reality

The reviewer notices that a comment overstates code, a defensive flag has no observable read, or a doc bullet contradicts impl — but drops because *"the headline bug isn't reachable through this comment."* The codebase remains in a state where the comment lies, but the review emits no finding.

> R5: notices `is_file()` doc says "covers unreadable path" while mode-0000 files pass the check. Drops to "residual-risk note" because the historic `os error 2` chain doesn't flow through there. The doc-overclaim remains in the tree.

This systematically suppresses custom-review's strongest niche (doc-vs-impl-lies, n=4 across R5/R6/R8/R10). The v2 finding-promotion rule: false-claim → Low. True-claim → drop. Reachability is not the question. The impact statement makes the audience explicit: *"maintainers will act on a false model."*

### 14. Render-lifecycle elided

The reviewer correctly traces operation ordering ("mode flip → drain → spawn") but conflates *"operation queued"* with *"user sees outcome."* The candidate is emitted with an impact statement that names a user-visible artifact without tracing the actual render path through suspend/restore, mount/unmount, modal-queue survival, or alt-screen entry/exit.

> R10 F2 (custom-review's first dataset overstatement): traces that the modal is queued before the editor spawns. Claims the modal renders *under* the editor session. Misses that the alt-screen suspension defers rendering until after the editor returns. The user never sees a modal-under-editor; the candidate is wrong.

The v2 visibility-dependent finding-shape requires `Render proof:` (one-sentence trace of the render path with file:line at each step) or `Test proof:` (citation of a test asserting the visible outcome). No proof line → not a finding. The candidate drops or moves to Open Questions if the uncertainty itself is Critical/High.
