# Claude failure modes

Seventeen archetypes of Claude reviews missing bugs. Read at workflow step 7 — for each candidate about to promote, run down the table and ask whether the candidate is immune to each mode. If one or two feel load-bearing, return to the named workflow step before promoting.

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
| 12 | Read the diff as self-contained | 3 (claims) + 7 (producer-claim shape) | Producer looks correct; the actual read site reads `Default::default()` / fallback / stale cache. |
| 13 | Trigger-shy on claim-vs-reality | 7 (claim-vs-reality finding-shape) | Reviewer notices a comment lying; drops because "headline bug isn't reachable through it." |
| 14 | Render-lifecycle elided | 7 (visibility finding-shape) | "Modal renders under editor" without proving the alt-screen suspend/restore actually re-renders. |
| 15 | Validated components in isolation | 3 + 5 (compose) + 7 | Each handler/gate/task is individually sound; the bug is in the keystroke→commit→output composition, a discarded return value, or a finalize that reads only one of several teardown bounds. |
| 16 | Sibling-path behavior asymmetry | 5 (sibling parity) | New path mirrors an existing sibling but silently does *less* — no response-attach, wrong per-transport default, error mapped to the wrong terminal state. Compiles and unit-tests green. |
| 17 | Claim-true gate over-fired | 7 (claim-vs-reality carve-out) | Dropped a real behavioral bug as `claim-currently-true` because the comment describing the broken behavior was literally accurate. |

## Detailed examples — the modes that drove this skill's core design changes

Modes 12, 13, and 14 are the gates encoded as finding-promotion rules in `SKILL.md`. The table is enough for modes 1–11 (their fix is embedded in the workflow steps). These three deserve a fuller treatment because they recur even on code the reviewer has seen many times.

### 12. Read the diff as self-contained

The reviewer treats the changed files as the universe of the review. For a new producer (writer, dispatch arm, editor, settings store), the question *"what does the consumer actually read at the effect site?"* is never asked. The producer looks correct in isolation. The consumer either defaults to an unrelated source of truth, is itself unwired, or reads through a dead code path.

> Example: a new editor writes `config.toml` and `Ctrl+g` saves successfully, but the engine command that should read the new file resolves against `AgentPermissionsConfig::default()` instead. The feature ships dead. The diff looked self-contained; the dead-wired consumer was outside the changed files.

This is the single highest-leverage class this gate exists to catch. The producer-claim finding-shape forces the question. The trap is a named consumer that reads `Default::default()` or an unrelated config — a named consumer that doesn't actually read the produced value is theater. Deliberately search: `Default`, `default()`, `unwrap_or_default`, fallback constructors, old config paths, old enum arms.

### 13. Trigger-shy on claim-vs-reality

The reviewer notices that a comment overstates code, a defensive flag has no observable read, or a doc bullet contradicts impl — but drops because *"the headline bug isn't reachable through this comment."* The codebase remains in a state where the comment lies, but the review emits no finding.

> Example: the reviewer notices an `is_file()` doc says "covers unreadable path" while mode-0000 files pass the check, but drops it to a "residual-risk note" because the historic `os error 2` chain doesn't flow through there. The doc-overclaim remains in the tree.

This systematically suppresses one of the review's strongest niches (doc-vs-impl-lies). The finding-promotion rule: false-claim → Low. True-claim → drop. Reachability is not the question. The impact statement makes the audience explicit: *"maintainers will act on a false model."*

### 14. Render-lifecycle elided

The reviewer correctly traces operation ordering ("mode flip → drain → spawn") but conflates *"operation queued"* with *"user sees outcome."* The candidate is emitted with an impact statement that names a user-visible artifact without tracing the actual render path through suspend/restore, mount/unmount, modal-queue survival, or alt-screen entry/exit.

> Example: the reviewer traces that a modal is queued before the editor spawns and claims the modal renders *under* the editor session — missing that the alt-screen suspension defers rendering until after the editor returns. The user never sees a modal-under-editor; the candidate is wrong.

The visibility-dependent finding-shape requires `Render proof:` (one-sentence trace of the render path with file:line at each step) or `Test proof:` (citation of a test asserting the visible outcome). No proof line → not a finding. The candidate drops or moves to Open Questions if the uncertainty itself is Critical/High.

## The cross-component classes (modes 15–17)

Modes 15, 16, and 17 are the classes a review that validates each component *in isolation* misses but a holistic cross-component read catches. Unlike modes 12–14, their mechanics and worked examples live entirely in the bug-patterns, so they need no separate detail here — the table row plus the cited pattern is enough:

- **15 (validated in isolation)** → compose the full path and assert the output: `bug-patterns.md` #19 step 3 (UI→command→output edit chains), #20 (returned-value discarded), #21 (cross-async-task teardown).
- **16 (sibling-path asymmetry)** → the sibling behavior-parity diff: `bug-patterns.md` #3.
- **17 (claim-true gate over-fired)** → the claim-true-but-behavior-wrong carve-out: `SKILL.md` § *Claim-vs-reality findings*.

**Preflight question 13 is the consolidated gate.** The standing lesson: when a change spans more than one component, *compose the path and diff the sibling* — do not certify the whole from individually-correct parts.
