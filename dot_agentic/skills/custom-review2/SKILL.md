---
name: custom-review2
description: Use when an in-depth correctness review of pending code is wanted — PR/diff review, implementation QA, ADR/spec compliance checks, regression hunting, "is this change safe to merge", or review-style questions about whether code changes are safe. Performs a read-only review that promotes findings only when proof of condition, wrong behavior, and concrete impact lives at file:line. Producer-claims must name the actual source of truth at the effect site; user-visible claims must cite a render path or test; doc/comment/dead-state claims are gated on whether the codebase currently claims something false. Unverified suspicions drop to Open Questions or are discarded. Heavier than `/review`; use when depth matters more than speed.
---

# Custom Review (v2)

A read-only review with **two review artifacts and one diff capture**: `notes.md` is the enforcement substrate (mandatory; mandatory inline structure forces falsification depth, candidate accounting, severity anchoring, and return loops); `review.md` is the rendered output. `diff.patch` is a supporting capture, not a review artifact.

The v1 skill wrote seven artifact files. The v2-1 (this) version collapses that to two review artifacts while preserving v1's anti-skipping enforcement — what was paperwork in v1's pipeline becomes mandatory inline sections in a single notes file. Empirical lesson from R11/R12: making the ledger optional and dropping per-claim falsification depth turned the skill into a shallower variant of itself; this version restores both without the seven-file ceremony.

## Core principle

Do not review the diff as isolated edited lines. First identify the behavior, contract, or invariant the change claims to preserve or introduce. Then try to falsify that claim by tracing producer → actual source of truth at the effect site → user/operator observable. A finding exists only when you can name **the condition, the actual wrong behavior, and the concrete impact**, with file:line evidence you have re-read at every link.

The reviewer optimizes for *not emitting unproven findings*, but with explicit anti-trigger-shy machinery: every reachable-defect line is committed to the candidate ledger before it can be dropped, and every drop reason is written. Unverified suspicions become Open Questions only when the uncertainty itself is high-risk — they do not become hedged findings.

## Read-only

You MUST NOT modify any file outside `tmp/custom-review-<timestamp>/`. You MUST NOT switch branches, stash, reset, checkout, or otherwise alter the working tree.

You MAY: read any file, run `git`, `grep`, `rg`, run tests/typecheck/lint/builds when they would surface signal (treat results as evidence, never as proof), write the mandatory `notes.md` and `review.md` (and the supporting `diff.patch`) under `tmp/custom-review-<timestamp>/`.

You MUST NOT: edit any file outside `tmp/custom-review-<timestamp>/`, auto-fix anything you find, run `git checkout`, `git switch`, `git stash`, `git reset`, `git restore`, `git clean`, or any command that mutates working-tree state.

## Hard preconditions

Refuse with a short, clear message if:

1. **No target is determinable** per the resolution table — neither a git-based target nor explicit file paths/snippets.
2. **Git-based target with empty diff.** For `branch`/`uncommitted`, `git diff <base>...HEAD --stat` (resp. `git status --porcelain`) must be non-empty. For `pr`, `git diff <base_ref>...<head_ref> --stat` (refs from `gh pr view`) must be non-empty. If `<head_ref>` is not present locally, fetch it read-only first: `git fetch origin pull/<num>/head:refs/custom-review/pr-<num>` and use that ref. Never switch branches or touch the working tree.
3. **PR target with unpushed local commits or diverged branch.** After resolving `<head_ref>` (branch name) and `<head_oid>` via `gh pr view <num> --json headRefName,headRefOid`, check whether `refs/heads/<head_ref>` exists locally and whether its tip equals `<head_oid>`:
   - Local **ahead** (`git merge-base --is-ancestor <head_oid> refs/heads/<head_ref>` exits 0): refuse with `Local branch <name> has N unpushed commit(s); GitHub still shows the old code. Push the commits and re-run.` Print `git log --oneline <head_oid>..refs/heads/<head_ref>`.
   - Local **behind**: proceed; GitHub is source of truth.
   - **Diverged** (neither ancestor of the other): refuse with `Local branch <name> has diverged from GitHub's PR head (likely pending force-push). Push the rewritten branch and re-run.`

   The branch being checked is the PR's head branch *by name*, NOT the operator's currently-checked-out branch. Resolve and inspect `refs/heads/<head_ref>` specifically. Also check `git worktree list --porcelain` — the same ref applies regardless of where it's checked out. The check uses only `git rev-parse` and `git merge-base --is-ancestor`; nothing is mutated. PR-target only — for `branch`/`commit`/`uncommitted` the local working state IS what gets reviewed.
4. **PR re-review with stable head + dirty worktree.** When a prior `tmp/custom-review-*/review.md` exists for the same PR at the same `<head_oid>` (compare against the prior `review.md`'s mandatory metadata header — see *Output structure*), run `git status --porcelain` and check whether any modifications touch files in `git diff <base_ref>...<head_ref> --name-only`. If yes, do NOT re-emit prior findings as still-open — review against the worktree state and report: `PR head unchanged since prior review; worktree has uncommitted modifications on N of the diff's files. Reviewing against worktree state. Recommend the operator commit and push these fixes before the next round.` This guards against R7-style stale re-emission. The lookup uses `review.md` since it is the public output; `notes.md` may also be checked for additional context about a prior run.

   **Legacy prior reviews:** ignore any prior `review.md` that does not contain the `custom-review-meta` header block at the top. Those predate this guard and cannot be reliably matched to a `<head_oid>`. Proceed as a fresh review.

## Target resolution

| Pattern | Target | Notes |
|---|---|---|
| `<number>` or PR URL | `pr` | Resolve head/base refs via `gh pr view <num>`. Diff: `git diff <base_ref>...<head_ref>` (three-dot, merge-base). Read files at PR state via `git show <head_ref>:<path>`. If `<head_ref>` not local, fetch read-only with `git fetch origin pull/<num>/head:refs/custom-review/pr-<num>`. Never switch branches. |
| `against <branch>` / `vs <branch>` | `branch` | Explicit base. Diff: `git diff <base>...HEAD`. |
| `<40-hex-sha>` or `commit <sha>` | `commit` | Diff: `git diff <sha>^..<sha>`. Operator may supply `<sha>^1..<sha>` for merge-commit first-parent diffs. |
| `uncommitted` / `staged` / `working tree` / `wip` | `uncommitted` | Diff: `git diff HEAD`. |
| Explicit file paths or globs | `paths` | Static review of files-as-they-stand. No diff. |
| Pasted code blocks | `snippet` | Static review of pasted code. No diff, no repo dependent-search. |
| Not in git AND no paths/snippet | (refuse) | Ask operator for paths. |
| Nothing useful, in git repo | `branch` (default) | Base = `gh repo view --json defaultBranchRef -q .defaultBranchRef.name` || `main`. |

**Trailing focus text.** Operator input that does not match a target spec is treated as an `Additional focus:` directive — biases falsification toward the focus area, mentioned in coverage. It does NOT narrow scope; the broad pass still runs.

For `paths` and `snippet` targets: claims are about what the code currently promises to its callers/users (phrasing drops the "now"). For `snippet`, dependent search is unavailable — note this in coverage. A mandatory caveat appears in the rendered review: *"This review used the `<paths|snippet>` target — no diff was inspected. Behavioral regressions introduced by a prior commit are out of scope."*

If the target is genuinely ambiguous, ask one short multiple-choice question.

## Workflow

A single-pass review whose discipline lives in the **mandatory `notes.md` structure** (see *Notes file* below). The steps below are numbered; cross-step return loops are listed explicitly and are mandatory when triggered.

The three files written this skill: `tmp/custom-review-<ts>/diff.patch` (supporting capture), `tmp/custom-review-<ts>/notes.md` (review artifact — enforcement), `tmp/custom-review-<ts>/review.md` (review artifact — output). Only the two `.md` files are review artifacts; `diff.patch` exists so later steps can grep without re-running git.

### 1. Resolve target & save the diff

Per the table above. For diff-based targets, save the raw diff once to `tmp/custom-review-<ts>/diff.patch`. Capture `git diff <base>...<head> --stat` for file/line counts. Note `git status --porcelain` for dirty-worktree state. For PR targets, record `head_ref`, `base_ref`, `head_oid` so later file reads use `git show <head_ref>:<path>`.

### 2. Read sources of truth & prime patterns

Read, in order:

- Repo-root `CLAUDE.md`, `AGENTS.md`, `GEMINI.md` (or `CONTRIBUTING.md` if present).
- For `pr` target: PR title and body via `gh pr view <num> --json title,body`.
- Any `ADR-*.md`, `docs/adr/`, `docs/decisions/`, `docs/rfcs/`, `docs/specs/` files **touched by the diff or named in the PR body**.
- Each touched migration / schema file in full (`*.sql`, `prisma/schema.prisma`, `*_pb.proto`, `models.py`, etc.).
- **The `cue` column of `reference/claude-failure-modes.md`** (full table, single-line cues only) — primes the sideways search at step 7.
- **The class-triggered lookup table at the top of `reference/bug-patterns.md`** — note which classes the diff will touch; full sections are read at step 6.

**ADR/spec drift sweep.** Extract concept terms from touched files (top-level directory names, basenames-without-extension, exported identifiers visible in hunk headers). Run one `rg -l '<term1>|<term2>|...'` across `docs/adr/`, `docs/specs/`, and any `adr/` or root `ADR-*.md`. Read every match in full. Untouched ADRs whose normative claims appear contradicted by the change are candidates for the doc-vs-impl-lies class — record them on candidate lines in step 8.

**Adjacent comments are claims.** For every touched code path, re-read the comments and docstrings immediately surrounding the change as if they were doc-bullets. A comment that overstates or contradicts the new code is a `claim-vs-reality` candidate.

### 3. Enumerate surfaces

Open `notes.md` and write the **`## Surfaces`** section: every changed semantic surface — fields, types, enum variants, statuses, routes, endpoints, query/cache keys, event/job/queue names, feature flag keys, config keys, permission names, database columns, serialization names, exported helpers/hooks/components, public types, public functions, env vars, error codes, log keys, metric names. **Deletions count.**

For each surface, refine `grep_terms` so the list includes the actual identifiers AND every serialized alias (camelCase ↔ snake_case ↔ kebab-case, route slugs, DB column variants, old form after rename). A broad `grep_terms` recreates v1's process tax at step 7; a narrow one misses sibling producers.

`## Surfaces` is mandatory. Refer to *Notes file* for the exact line shape.

### 4. Completeness audit (early gate)

Per the *Subagents* section: spawn a completeness-audit subagent (`subagent_type: general-purpose`) when the diff `changed_files > 5 OR semantic_surfaces > 5 OR any contract boundary touched`. Inputs: `scope` summary, `diff.patch`, the `## Surfaces` block. Instruction: *"independently re-derive the semantic surfaces this diff touches; report only what is missing from the surfaces list or what looks misclassified; do not propose findings; do not edit any file."*

Add returned missing surfaces to `## Surfaces` before step 5. **Mandatory return loop:** if a surface was added, the new surface must be falsified at step 6 and its hits classified at step 7.

For docs-only or tests-only diffs that touch no normative behavior, skip with one-line reason on the subagent line.

### 5. State claims

Write `## Claims` in `notes.md`. For each meaningful change in the diff, one falsifiable statement:

> The code now promises X. X is false if Y.

Refactor-claims (*"no behavioral change"* — often the most violated) and deletion-claims (*"the removed thing is unused"*) count. **No claim cap.** If you end up with more than 8 claims, group by root-cause concept — but the group's falsifications at step 6 must still cover each member's distinct surface. Grouping is organizational, not skipping.

Each claim block carries:
- `tier:` — the rubric tier (`observable-wrong-behavior` / `silent-state-divergence` / `contract-violation-not-yet-visible` / `procedural-doc-drift` / `comment-precision` / `N/A`). The tier anchors severity at step 9; refactor-parity claims start at `N/A` but must be escalated to a real tier the moment parity breaks.
- `surfaces:` — the `Sn` IDs from step 3 the claim covers.
- A `producer-realization:` line for any claim about a new producer (writer / dispatch arm / editor / setter / event emitter / status field / persisted record / config key / exported helper that affects current behavior). The fields:
  ```
  producer-realization: producer=<file:line>; produced=<value>; intended-consumer=<concept>; actual-read-site=<TBD-until-step-7|file:line>; source-of-truth-at-read=<TBD-until-step-7|concrete>; observable-effect=<one-line>
  ```
  Start the row with `actual-read-site` and `source-of-truth-at-read` deferred to step 7; finalize after sideways search. A finalized row that reveals the consumer reads `Default::default()`, `unwrap_or_default`, an unrelated config, a stale cache, or a dead branch — or no consumer at all — is the producer-dead class (R10 P1, R6 assemble, R7 TUI rollback). Promote a candidate immediately.

### 6. Falsifications & sub-checks (≥3 + four sub-checks per claim)

For each claim in `## Claims`, write **≥3 falsification lines** plus four sub-check lines. Each falsification has a result tag (`disproved` / `reachable-defect` / `open-question`) with a one-line reason. Each sub-check is one of `finding | checked-no-issue | N/A reason=...`:

- `backward_compat` — old data in DB, old clients calling API, old configs/feature flags, old enum values in persisted state, old URLs in shared links, cached state, persisted UI state.
- `failure_parity` — error / loading / empty / cancel / retry / timeout / permission-denied / partial-success paths.
- `async_invalidation` — every event that should cancel in-flight work, not just replacement requests.
- `deletion_orphans` — for deletion-claims, what still references the removed thing (docs, metrics, configs, flags, monitoring, tests, generated code).

Before writing falsifications, **read the bug-patterns sections triggered by this diff's classes** (typically 2–4 of the 17) from `reference/bug-patterns.md`. Prime attention; do not tick mechanically.

`inconclusive` may appear transiently but must resolve to `disproved` / `reachable-defect` / `open-question` before step 8.

For trailing focus text, add ≥1 extra falsification per claim that targets the focus area. Focus directives do not narrow scope.

### 7. Search sideways & classify every hit at high-risk roles

For every surface in `## Surfaces`, search using the surface's `grep_terms`. Classify every non-generated hit into a role:

`producer | consumer | transformer | serializer | storage | migration | validation | permission | cache | ui-render | test | doc | generated | irrelevant`

**Fully read every hit in producer / transformer / serializer / storage / migration / validation / permission / cache roles** — these are the falsifying-evidence roles. For mechanically similar hits, batch with `count=N pattern=<...> rationale=<one-line>` and read one representative; do not silently sample.

Use the results to:
- Finalize any deferred `producer-realization:` lines in `## Claims`.
- Update the falsifications in step 6 (return loop): a hit at a high-risk role that contradicts a `disproved` result re-opens that line.
- Surface sibling workflows the model missed: create/edit, single/bulk, admin/user, mobile/desktop, success/error/loading/empty, initial/retry/cancel, deletion-mirror.

Stop expanding when remaining paths no longer cross a changed contract boundary.

### 8. Read tests as artifacts + build the candidate ledger

For every test file touched by the diff AND every test file discovered while tracing claims at steps 6–7:

- **Fixture blindness:** what does the fixture make impossible to fail?
- **Assertion correctness:** does the assertion encode the regression?
- **Coverage gaps:** which `reachable-defect` lines from step 6 does this test not cover?

A test that *"passes when the bug is present"* (fixture-blindness, wrong-assertion, missing-visible-outcome assertion) is itself a candidate — its severity scales to the underlying defect.

Now write `## Candidates` in `notes.md`. Every `reachable-defect`, `open-question`, sub-check `finding`, finalized-and-dead producer-realization line, ADR-drift hit, test-derived defect, and dead/defensive-state observation gets a `Kn` line. Each line ends with a status:
- `verified-finding-Fn` (after step 9 promotion)
- `open-question-OQn`
- `dropped reason=<one-line>` (guard-found at file:line / disproved-by-adversarial-verification / no-render-path-proof / claim-true / not-yet — every drop has a substantive reason)

The candidate ledger is what defeats trigger-shyness. A candidate that is never written cannot be dropped with a reason; the only way to drop is to write it down first.

### 9. Promote candidates to findings

For each `reachable-defect` candidate:

1. Re-open the primary cited file at the cited line with 30–80 lines of context.
2. Re-open every supporting file the candidate depends on: producer, consumer, sibling, test, source-of-truth doc.
3. Apply the **finding-promotion rules** below. Confirm the promotion is consistent with the claim's `tier:` (or declare a tier escalation on the `Kn` line with a one-line reason).
4. If the re-read reveals a guard:
   - Guard fully prevents the failure → drop the `Kn` line with reason `guard-found at <file:line>`.
   - Guard narrows the condition → rewrite the candidate; return to step 6 to re-check the claim's sub-checks; the tier may shift.
   - Guard makes the path less common but still reachable → keep at lower severity within the tier's floor/ceiling.

The candidate's `Kn` line moves to `status=verified-finding-Fn` for promoted, `status=open-question-OQn` for high-risk uncertainty, or `status=dropped reason=<...>` otherwise.

### 10. Adversarial verification (post-promotion gate)

Per the *Subagents* section: spawn an adversarial verifier (`subagent_type: general-purpose`) for **every Critical/High finding, every cross-file Medium where the proof depends on multiple real layers or non-test files, and every visibility-dependent finding**. Input: the finding text + every cited file:line. Instruction: *"try to disprove this finding. Read only the cited locations and their surroundings. Return one of: `holds <reason>` / `disproved <reason and citation>` / `narrows <revised condition>` / `unsupported <missing evidence>`. Do not extend the search; do not propose new findings."*

Verdict handling:
- `holds` → keep finding.
- `disproved` → drop the `Kn` line with `reason=disproved-by-adversarial-verification` + verifier's citation.
- `narrows` → rewrite finding; return to step 6 to re-check the claim's sub-checks.
- `unsupported` → return to step 9's re-read with the verifier's gap; if not closed, drop.

Skip for purely local Low findings — the operator's own re-read at step 9 is the check at that scale.

### 11. Failure-mode preflight & write outputs

Silently answer the 11-question preflight (one line each, internal; not printed to chat). Any "no" returns to the named step and re-runs everything downstream:

1. (step 2) Did I read CLAUDE.md / AGENTS.md / ADRs, run the ADR drift sweep, and prime patterns?
2. (step 7) Did I extend past changed lines into producers, consumers, and downstream effects?
3. (step 8) Did I read touched tests as artifacts — fixture blindness, assertion correctness, coverage gaps — rather than as proof?
4. (step 6) Did I treat refactor-claims as falsifiable and look for behavioral drift?
5. (step 7) Did I enumerate sibling axes for every claim that has them?
6. (step 6) Did I check error / loading / empty / cancel / retry / timeout / permission-denied / partial-success paths?
7. (step 7) Did I search producers AND consumers of every changed surface and classify every hit?
8. (step 9 / step 10) Did I drop every unverified suspicion instead of hedging it into a finding?
9. (step 6) Did I check async invalidation — every event that should cancel in-flight work?
10. (step 6 / step 7) Did I separate UI gating from server-side authorization for every permission-touching change?
11. (step 6) Did I check backward compatibility against old data / old clients / old configs / old enums / cached state / persisted UI state?

Record exactly `preflight: passed` in `## Preflight` once all questions are "yes" and downstream rework is complete. Do not render `review.md` while a `returned-to=<step>` state is open; `returned-to` is transient.

Render `review.md` per *Output structure* below and `reference/output-format.md`. Findings first, ordered by severity then root-cause group; Open Questions; Coverage footer.

## Risk-aware small mode

For diffs where ALL of the following are true:

- `changed_files ≤ 5`
- `≤ 300 changed lines`
- no contract-boundary touch from this list: auth / permissions / authorization gates, persistence (DB schema, migration, on-disk format), wire format (serialization, public API, RPC, RPC error codes), cross-process or cross-machine state, async cancellation / request invalidation, public type / exported function / hook signature, config keys / env vars / CLI flags, feature flags, query/cache keys, persistent UI state, background jobs / events / queues, identity / tenant / org boundaries, payment / account / core workflow paths, old-data / rollout compatibility, ADR / spec / runtime-model.md
- no producer-claim with a non-trivial consumer

… reduce step 4 and step 10 subagents to skipped (one-line reason on the subagent line) and relax step 6 to ≥1 falsification per claim with two sub-checks (`failure_parity` + `backward_compat`) per claim. `notes.md` and the step 11 preflight remain mandatory.

**Escape hatch (mandatory).** If during the review any candidate is assessed Critical / High / cross-file Medium / visibility-dependent, escalate to normal mode immediately: adversarial verification applies, the full four sub-checks for that claim become mandatory.

## Notes file

`tmp/custom-review-<ts>/notes.md` is **mandatory**, not optional. Its structure carries the enforcement that v1 spread across seven files. See `reference/notes-file.md` for the template; the mandatory sections are: `## Surfaces`, `## Claims`, `## Candidates`, `## Coverage`, `## Preflight`.

The meta-fixer / operator adjudicates only `review.md`. `notes.md` is reviewer-internal — used by the reviewer to enforce the workflow on itself; not credit-bearing for benchmarking.

## Finding-promotion rules

A candidate becomes a finding **only when its text carries the proof.** No upstream artifact substitutes for proof in the finding itself.

### General

Every finding must include:

- **Primary site** as `path:LINE`.
- **Condition** — the input, state, or timing under which the failure occurs.
- **Behavior** — what the code actually does (declarative, present tense).
- **Mechanism** — *why* it does that, naming the specific construct (missing guard, wrong predicate, race window, dead read site).
- **Impact** — what the user/data/system/caller observes. Concrete consequence, not *"could lead to issues."*
- **Fix direction** — one sentence pointing at where and how. Not a rewrite.

If you cannot supply all of these, the candidate cannot be a finding. Drop, move to Open Questions, or compress to a Residual Risk line in coverage.

### Producer-claim findings

A producer-claim finding's text MUST name: the producer (file:line), the produced value, the actual read site (file:line), the actual source of truth at that read site, and the observable effect. Example shape:

> `src/editor.rs:120` writes `agent_permissions` to `config.toml`, but the command path at `src/engine.rs:211` constructs permissions from `AgentPermissionsConfig::default()` instead of reading that file. So `Ctrl+G` saves successfully while the engine continues using defaults.

That sentence contains producer / produced value / actual read site / source of truth / effect, all without a schema. No separate `[Cr]` record needed.

### Visibility-dependent findings

If the finding's impact statement names a user-visible artifact (modal, banner, error message, status line, toast, screen redraw, alt-screen content), the finding MUST carry one of:

- **`Render proof:`** — a one-sentence trace of the render path through any suspend/restore / mount/unmount / modal-queue / alt-screen / focus boundaries, citing file:line for each step.
- **`Test proof:`** — citation of a real test (`tests/path:line` or in-source `#[test]`) whose assertion would fail if the visible-behavior claim holds. The test must assert the visible outcome, not just the upstream queue/operation state.

If neither proof is available, the candidate is not a finding. The default disposition is **drop** (or surface as a one-line Residual Risk in coverage if it has weak Low-severity merit). Move to Open Questions only when the uncertainty itself is Critical/High — i.e. a real possibility of user-visible breakage where the missing render-path/test evidence is what blocks confirmation. This matches the Open Questions policy in `output-format.md` (the safety valve is for high-risk uncertainty, not for "I noticed but couldn't prove" candidates).

This blocks the R10 F2 class: tracing operation order correctly (mode flip → drain → spawn) but conflating *"operation queued"* with *"user sees outcome"* without proving the render path.

### Claim-vs-reality findings (doc / comment / dead-state)

For candidates whose defect is *"the codebase claims something false"* (comment overstates what the code does; doc bullet contradicts impl; defensive flag with no observable read; dead dispatch arm; stale section in a runtime-model doc), the verification gate is **NOT** *"is the headline bug reachable through this?"* — it IS *"is the claim currently false?"*

- Claim currently false → finding. Severity floor: Low. Severity ceiling: Medium (per the severity rubric in `output-format.md`). Promote to High only if a documented future consumer is in the same PR and the false claim will mislead them.
- Claim currently true → drop the candidate.
- *"The headline bug isn't reachable through this comment"* is NOT a valid drop reason. The codebase still claims something false regardless of whether the original bug is reachable.

The "for whom does it break?" question for these findings is *"maintainers will act on a false model"* — make that explicit in the impact statement.

This is custom-review's strongest demonstrated niche (doc-vs-impl-lies n=4 across R5/R6/R8/R10). It fires only when the gate is applied; trigger-shyness suppresses it.

### Test-derived findings

If a touched test makes a regression impossible to fail (fixture blindness, assertion encodes the bug, no assertion on the visible outcome), promote that as a finding with severity scaled to the underlying defect. Cite the test path:line and one sentence on what the fixture makes impossible.

## Subagents

The main reviewer owns claims, severity, grouping, wording, and whether a finding is real. Subagents gather or challenge evidence; they never produce findings, severity, or final synthesis.

### Completeness-audit (step 4)

`subagent_type: general-purpose`. **Mandatory** when `changed_files > 5 OR semantic_surfaces > 5 OR any contract boundary touched`. Skip with one-line reason for docs-only / tests-only diffs that touch no normative behavior.

Inputs: scope summary, `diff.patch`, the current `## Surfaces` block.

Instruction: *"You are a completeness auditor. Independently re-derive every semantic surface this diff touches (fields, types, enums, statuses, routes, query/cache keys, event/job names, config keys, permissions, columns, serialization names, exported helpers, public types/functions, env vars, error codes, log keys, metric names — deletions count). Report ONLY surfaces missing from the provided list or surfaces that look misclassified. Do not propose findings. Do not assign severity. Do not edit any file."*

Add returned missing surfaces to `## Surfaces`; the new surfaces must be falsified at step 6 and have their hits classified at step 7 (mandatory return loop).

### Adversarial verifier (step 10)

`subagent_type: general-purpose`. **Mandatory** for every Critical/High finding, every cross-file Medium where the proof depends on multiple real layers or non-test files, and every visibility-dependent finding (one with `Render proof:` or `Test proof:` in its shape). Skip for purely local Low findings.

Inputs: the finding text from `review.md` draft + every cited `file:line`.

Instruction: *"You are an adversarial verifier. Read only the cited locations and their surroundings. Try to disprove this finding. Return exactly one of: `holds <reason>` / `disproved <reason and citation>` / `narrows <revised condition>` / `unsupported <missing evidence>`. Do not extend the search; do not propose new findings."*

Verdict handling per workflow step 10.

### Search partitioning (optional)

`subagent_type: general-purpose`. **Optional**, only when the diff exceeds ~15 files AND searches can be cleanly partitioned by disjoint subsystems. Each subagent owns one subsystem and returns classified hits (no findings, no severity). Most reviews do not need this.

### Never

Never use subagents for: stating claims, picking severity, writing the rendered review, or any final-synthesis work.

## Output structure

Print AND write the rendered review to `tmp/custom-review-<ts>/review.md`. The file MUST start with the metadata header below (it is what Hard precondition #4 uses to detect prior runs at the same head):

```
<!--
custom-review-meta
target: <pr#|sha|branch-name|HEAD|paths|snippet>
base_ref: <ref or N/A>
head_ref: <ref or N/A>
head_oid: <oid or N/A>
review_started: <ISO-8601 UTC>
-->

# Custom Review — <target description, one line>

<short two-line summary: target, base, scope, focus directive if any>

## Findings

<grouped by severity, then root-cause group; same-cause findings collapsed into one entry with multiple related_sites>

### Critical
<findings>

### High
...

### Medium
...

### Low
...
(omit any severity heading entirely when zero findings in that band)

## Open questions

<uncertain high-risk issues that could not be fully verified — bullet list with file:line and what would resolve the uncertainty>

## Coverage

- **Files inspected:** <count> (<key paths or directory groups>)
- **Commands run:** <git diff / rg / tests / typecheck / lint commands and results>
- **Subagents used:** <if any, with what they returned; omit if none>
- **Not checked:** <out-of-scope, with reason>
- **Residual risk:** <weak-confidence items that don't deserve a finding but matter>
- **Test gaps:** <missing coverage that matters>
```

### Per-finding rendering

The canonical finding shape — including the `Render proof:` / `Test proof:` lines for visibility-dependent findings, the producer-claim sentence shape, and the claim-vs-reality impact shape — lives in `reference/output-format.md` (§ *Finding shape*). Render every finding to that template; do not invent a variant.

### Hard output rules

- **Order by severity, then root-cause group.** Same-cause findings collapse to one entry with multiple `related_sites`. Never order by file.
- **ADR / spec / doc deviations are first-class findings** even if the code runs.
- **No hedging.** No `maybe`, `seems`, `possibly`, `might`, `appears to`. Uncertain high-risk → Open Questions. Low-confidence guesses → drop or compress to Residual Risk.
- **No confidence labels.**
- **No process narration**, no attribution, no praise filler, no time-spent mentions.
- **Skip list applies** — see `reference/output-format.md`.
- **Finding minimality.** Group by root cause; drop weak items to Residual Risk. Five clearly-actionable findings beat ten diluted ones.
- **Zero findings:** state it explicitly. Coverage + Residual Risk + Test Gaps still printed.

## Reference files

Read at the points named in the workflow, not as optional context.

| File | Read when | Purpose |
|---|---|---|
| `reference/notes-file.md` | Before step 3 (enumerate surfaces) | Mandatory `notes.md` template + class taxonomy for the candidate ledger. |
| `reference/bug-patterns.md` | Class-triggered lookup table at step 2; triggered full sections at step 6 (falsifications) | 17 heuristics priming attention to specific bug classes — read 2–4 sections per review. |
| `reference/claude-failure-modes.md` | Cue column at step 2; full archetype 12–14 detail consulted at step 9 if a candidate fits one of those classes | 14 archetypes of Claude reviews missing bugs — cues prime sideways search; detail catches blind spots before promotion. |
| `reference/output-format.md` | Before step 11 (write `review.md`) | Severity rubric, finding shape, skip list, coverage footer, zero-findings rule. |

## Failure modes — quick refusal table

| Failure | Action |
|---|---|
| Not in git AND no paths/snippet given | Refuse; ask operator for paths. |
| Empty diff (git target) | Refuse with `nothing to review`. |
| PR target — `<head_ref>` not present locally | Fetch read-only: `git fetch origin pull/<num>/head:refs/custom-review/pr-<num>`. Do not abort, do not checkout. |
| PR target — local branch ahead of GitHub's `<head_oid>` | Refuse with the unpushed-commits message in Hard preconditions #3. |
| PR target — local branch diverged from `<head_oid>` | Refuse with the diverged-branch message in Hard preconditions #3. |
| PR re-review — head unchanged, worktree has unstaged fixes on diff files | Review against worktree; report the worktree state per Hard preconditions #4. |
| Target ambiguous | Ask one short multi-choice question. |
| Operator passed `-` as trailing text | Ignore. |
| `gh` unavailable for PR target | Refuse. Without `gh pr view`, head/base ref names cannot be resolved reliably. Ask the operator for explicit head/base (e.g. `/custom-review2 against <base>` from a branch that tracks the PR head). |
| `tmp/` writes denied | Refuse — review cannot run without diff capture. |
| `paths` target — listed paths do not exist | Refuse; list missing paths. |
