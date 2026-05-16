---
name: custom-review
description: Use when an in-depth correctness review of pending code is wanted — PR/diff review, implementation QA, ADR/spec compliance checks, regression hunting, "is this change safe to merge", or review-style questions about whether code changes are safe. Performs a read-only review that forces depth before findings — claims are stated, falsified, verified at file:line, and only verified findings reach the printed review. Every finding lives somewhere on disk; unverified suspicions are dropped, not hedged. Heavier than `/review`; use when depth matters more than speed.
---

# Custom Review

A read-only review whose job is **force review depth before findings**. The skill runs seven ordered phases, each producing one named artifact under `tmp/custom-review-<timestamp>/`. The final rendered review prints only what survived literal re-read at the cited file:line; unverified suspicions are dropped.

## Core rule

Do not review the diff as isolated edited lines. First identify the behavior, contract, or invariant the change claims to preserve or introduce. Then try to falsify that claim across callers, producers, consumers, persistence, async state, permissions, docs, ADRs, tests, and sibling implementations. A finding exists only when you can name **the condition, the actual wrong behavior, and the concrete impact**, with file:line evidence you have re-read.

## Read-only

You MUST NOT modify any file outside `tmp/custom-review-<timestamp>/`. You MUST NOT switch branches, stash, reset, checkout, or otherwise alter the working tree.

You MAY: read any file, run `git`, `grep`, `rg`, run tests/typecheck/lint/builds when likely to surface signal (treat results as artifacts, never as proof), write artifact files under `tmp/custom-review-<timestamp>/`.

You MUST NOT: edit any file outside `tmp/custom-review-<timestamp>/`, auto-fix anything you find, run `git checkout`, `git switch`, `git stash`, `git reset`, `git restore`, `git clean`, or any command that mutates working-tree state.

## Discipline rules

These apply throughout every phase:

- **Artifacts are evidence, not paperwork.** Every entry carries reasoning, citation, or grep output — not summary. A surface with no hits gets one line, not a paragraph. A reviewer can satisfy seven files mechanically while reasoning poorly; don't. Volume is not quality.
- **Artifacts prove the search closed; they are not the review.** Do not paste full grep output. Cite line counts and representative lines instead. The artifact's job is to document that the work happened, not to reproduce it.
- **Forbidden marker values.** The tokens `todo`, `tbd`, `fixme`, `unclassified`, `unread`, `assumed`, `needs-read`, `verify` (meaning "not yet verified"), and `inconclusive` (outside the transient falsification → verification window) are forbidden **as structured field values** — e.g. `status=needs-read`, `result=tbd`. They are NOT forbidden as substrings of code identifiers, file paths, grep output, quoted comments, or natural-language notes. `verifyToken`, `unreadCount`, or a copied `// TODO: refactor` from the diff are all fine.
- **Return loops are mandatory.** If a later phase discovers something that invalidates an earlier phase's conclusions, return to that phase and re-do the affected work. Two specific return loops are called out below. The general rule: any new surface, narrowed condition, or contradictory evidence found late must be reflected backward, not appended forward.

## Hard preconditions

Refuse with a short, clear message if:

1. **No target is determinable** per the resolution table — neither a git-based target nor explicit file paths/snippets.
2. **Git-based target with empty diff.** For `branch`/`uncommitted`, `git diff <base>...HEAD --stat` (resp. `git status --porcelain`) must be non-empty. For `pr`, `git diff <base_ref>...<head_ref> --stat` (refs from `gh pr view`) must be non-empty. If `<head_ref>` is not present locally, fetch it first: `gh pr checkout <num> --detach` would work but mutates the working tree — instead use `git fetch origin pull/<num>/head:refs/custom-review/pr-<num>` and use that ref as `<head_ref>`. Never switch branches or touch the working tree.

## Target resolution

Parse the operator's trailing text into one of six target types:

| Pattern | Target | Notes |
|---|---|---|
| `<number>` or PR URL | `pr` | Resolve head/base ref names via `gh pr view <num>`. Diff command: `git diff <base_ref>...<head_ref>` (three-dot, merge-base). Read files at the PR state via `git show <head_ref>:<path>`. If `<head_ref>` is not local, fetch read-only with `git fetch origin pull/<num>/head:refs/custom-review/pr-<num>` and use that ref. The operator's current branch and working tree are irrelevant — never switch, stash, or checkout. |
| `against <branch>` / `vs <branch>` | `branch` | Explicit base. |
| `<40-hex-sha>` or `commit <sha>` | `commit` | Single commit. Diff command: `git diff <sha>^..<sha>` (equivalent to `git diff <sha>^!`). For merge commits this includes changes from all parents; if the operator wants only the first-parent diff (the changes the merge brought in), they must say `commit <sha>^1..<sha>` explicitly. |
| `uncommitted` / `staged` / `working tree` / `wip` | `uncommitted` | Diff = working tree vs HEAD. |
| Explicit file paths or globs in the repo | `paths` | Static review of files-as-they-stand. No diff. |
| Pasted code blocks | `snippet` | Static review of pasted code. No diff. No repo dependent-search. |
| Not in git AND no paths/snippet | (refuse) | Ask operator for paths. |
| Nothing useful, in git repo | `branch` (default) | Base = `gh repo view --json defaultBranchRef -q .defaultBranchRef.name` || `main`. |

**Trailing focus text.** Operator input that does not match a target spec is treated as an `Additional focus:` directive. It biases the falsification phase (extra falsification attempts targeted at the focus area) and is mentioned in the coverage footer. It does NOT narrow scope — broad-pass phases still run broadly.

If the target is genuinely ambiguous, ask **one** short multiple-choice question.

### Non-diff target modes (`paths`, `snippet`)

For `paths` and `snippet`, no diff exists. The phases still run with these substitutions:

- **Scope:** `target=paths` or `target=snippet`, `identifier=<list of paths or "pasted">`, `base=N/A`. For `snippet`, write the pasted code to `$DIR/inputs/`.
- **Model:** claims are about what the code **currently promises to its callers/users** — phrasing is `promise=The code promises that <X>.` (drop the "now"). Surfaces have `change=behavior-only`; `old_form` and `new_form` are identical.
- **Search:** for `paths`, search the rest of the repo for **consumers** of the file's exports. For `snippet`, dependent search is unavailable — record this and skip the closure rule for cross-file hits.
- **Falsification:** the backward-compat sub-check asks *"is the current code consistent with existing call sites of these exports?"* rather than *"are old data still handled."*
- **Review:** mandatory coverage caveat — *"This review used the `<paths|snippet>` target — no diff was inspected. Findings concern code-as-it-stands, not a specific change. Behavioral regressions introduced by a prior commit are out of scope."*

`paths` and `snippet` are intentionally fallbacks. Diff-based targets are stronger because they constrain the search space.

## Subagent policy

The main reviewer owns claims, severity, grouping, wording, and whether a finding is real. Subagents gather or challenge evidence; they never produce final findings or final synthesis.

**Spawn a subagent only when one of these is true:**

- `changed_files > 10`
- `semantic_surfaces > 8`
- the change crosses a **contract boundary**: API, schema, auth, permissions, serialization, migration, cache, async state, config, feature flag, or a public type
- any candidate is assessed as Critical or High after the main-thread re-read in the Verification phase (this triggers the adversarial-verification subagent specifically — see Verification phase)
- the reviewer cannot close a high-risk uncertainty alone

**Use subagents only for:**

- **Completeness audit** — independently re-derive semantic surfaces from the diff and flag what the model missed. (`subagent_type: general-purpose`)
- **Sibling discovery** — list candidate sibling paths; no findings. (`subagent_type: Explore`)
- **Search partitioning** — large reviews; each subagent owns disjoint surfaces and returns classified hits. (`subagent_type: general-purpose`)
- **Adversarial verification** — try to disprove a Critical, High, or subtle cross-file Medium candidate. (`subagent_type: general-purpose`)

**Never use subagents for:** stating claims, picking severity, writing the rendered review, or any final-synthesis work.

**Completeness audit trigger (specific):** run the completeness-audit subagent when

- `target=pr` AND `changed_files > 3`, OR
- `semantic_surfaces > 5`, OR
- the diff crosses a contract boundary, OR
- the main reviewer is unsure whether the surface inventory is complete.

For `target=pr` with `changed_files <= 3` and no contract boundary, either run the audit or record `skipped=true reason=tiny-local-pr-no-contract-boundary` in `search.md`.

## Initialize

```bash
TS=$(date -u +%Y%m%dT%H%M%SZ)
DIR="tmp/custom-review-$TS"
mkdir -p "$DIR"
```

Use TodoWrite to create one todo per phase below. Mark `in_progress` when you start, `completed` only when the phase's artifact passes its gate. Do not batch completions.

## Artifact format

All artifacts use **structured bullets** with stable IDs, required fields keyed `field=value`, and a lifecycle status where applicable. Tables fail on code-context reasoning; freeform prose fails on accountability. Structured bullets are the right middle.

Read `reference/artifact-schema.md` once before starting for the per-phase templates and ID prefixes.

The seven artifacts under `$DIR/`:

| Artifact | Owns | Phase that writes it |
|---|---|---|
| `scope.md` | What is being reviewed | Scope |
| `model.md` | Sources of truth, falsifiable claims, semantic surfaces | Model |
| `search.md` | Per-claim traces, classified hits, completeness audit, sibling-path inspection | Search |
| `falsification.md` | Per-claim falsification attempts; backward-compat / parity / async / deletion sub-checks | Falsification |
| `tests.md` | Test audit — fixture blindness, assertion correctness, coverage gaps | Tests |
| `verification.md` | Verified findings (structured); dropped candidates with reason | Verification |
| `review.md` | Rendered review printed to chat | Review |

---

## Scope phase

Goal: capture exactly what's being reviewed so later phases can't drift.

1. Resolve target type per the table above.
2. Determine the diff command for the target:
   - `branch`: `git diff <base>...HEAD` (three-dot — merge-base diff)
   - `pr`: `git diff <base_ref>...<head_ref>` (three-dot, merge-base). Resolve both refs via `gh pr view <num> --json headRefName,baseRefName,headRefOid,baseRefOid`. If `<head_ref>` is not present locally, fetch it read-only first: `git fetch origin pull/<num>/head:refs/custom-review/pr-<num>` and use `refs/custom-review/pr-<num>` as `<head_ref>`. File reads at the PR state use `git show <head_ref>:<path>`. Do not switch branches; the operator's working tree is not touched.
   - `commit`: `git diff <sha>^..<sha>` (two-dot, the changes in that commit). Operator may explicitly supply ranges like `<sha>^1..<sha>` for merge-commit first-parent diffs.
   - `uncommitted`: `git diff HEAD` (working tree vs HEAD)
   - `paths`: no diff — capture the full content of every listed path
   - `snippet`: no diff — record the pasted code
3. For diff-based targets: capture full diff output to `$DIR/diff.patch`; also capture `... --stat` for the file-count.
4. For `paths` / `snippet` targets: capture file contents (or pasted code) to `$DIR/inputs/`.
5. Note dirty-worktree state (`git status --porcelain`) and untracked-file count for git-based targets. For `pr` targets, also record `head_ref`, `base_ref`, `head_oid`, `base_oid` (from `gh pr view`) in `scope.md` so later phases read files via `git show <head_ref>:<path>` rather than via the working tree.
6. Capture operator focus text verbatim.

**Write `$DIR/scope.md`** per `artifact-schema.md`.

**Gate:** every field in the schema is filled or carries an explicit `N/A reason=...`. No forbidden marker values.

---

## Model phase

Goal: before reading a line of changed code, know what the change is supposed to mean (claims), what backs that meaning (sources of truth), and what surfaces it touches (semantic surfaces).

### Sources of truth

**Mandatory reads (skip only if file absent; record absence in `model.md`):**

- Repo-root `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`.
- `CONTRIBUTING.md` if present.
- Any `ADR-*.md` / `adr/`, `docs/adr/`, `docs/decisions/`, `docs/rfcs/`, `docs/specs/` files **touched by the diff or referenced from the diff**.
- For `pr` target: PR description (`gh pr view <num> --json title,body`) and any in-repo or external doc URLs in the body.
- Each touched migration / schema file in full (`*.sql`, `prisma/schema.prisma`, `models.py`, `*_pb.proto`, etc.).

**ADR/spec drift sweep (mandatory).** The touched/referenced filter misses untouched ADRs that the code change silently violates — exactly the kind of finding the skill advertises.

1. From `scope.md`, extract concept terms: top-level directory names of touched files (e.g. `src/auth/...` → `auth`), basenames-without-extension of touched files, identifiers visible in diff hunk headers or in added/removed lines as exported symbols.
2. List the standard ADR/spec locations present in the repo (typically `docs/adr/`, `docs/decisions/`, `docs/rfcs/`, `docs/specs/`, plus any `adr/` or `ADR-*.md` in the root). Skip if none exist.
3. Run a single ripgrep across all candidate locations: `rg -l '<term1>|<term2>|...' docs/adr/ docs/specs/ ...`. Read every match in full.
4. Record each match in `model.md` (sources section) with `touched=no` and `relevance=<high|medium|low>` based on whether the doc makes a normative claim about a concept the diff touches. Note `potential_drift=<ADR-id>` on any source whose normative claim appears to be contradicted by the change.

**Source-of-truth conflicts.** When two sources disagree (an ADR says X, tests assert not-X, the PR description says Z), do not silently pick one. Record the conflict as a source-of-truth record with `kind=conflict` and name which authority you treat as governing (or `unresolved` — an unresolved conflict is itself a candidate finding for the Falsification phase).

### Claims

For each meaningful change in the diff, state a **falsifiable claim**:

> The code now promises X. X is false if Y.

Refactors are claims too (a refactor-claim is *"no behavioral change"* — often the most violated). Deletions are claims too (a deletion-claim is *"the removed thing is unused"* — check docs, metrics, configs, flags, tests).

### Surfaces

Enumerate every changed semantic surface: fields, types, enum variants, statuses, routes, endpoints, query/cache keys, event/job/queue names, feature flag keys, config keys, permission names, database columns, serialization names, exported helpers/hooks/components, public types, public functions, environment variables, error codes, log keys, metric names. **Deletions count.**

For each surface, identify the **search strings** (`grep_terms`) Phase Search will use. `grep_terms` is the authoritative search list — descriptive `old_form` / `new_form` labels are not used as literal searches. For added surfaces, `old_form=N/A`; for removed, `new_form=N/A`; `grep_terms` always carries the actual identifiers.

**Write `$DIR/model.md`** per `artifact-schema.md` — one section each for sources, claims, surfaces. Cross-link surfaces to claims via `claim_refs=C1,C3`.

**Gate:** every meaningful change in the diff appears in at least one claim. Every claim has a `falsified_if`. Every surface has either `grep_terms=<list>` or `grep_terms=none` with a written closure plan. No forbidden marker values.

---

## Search phase

Goal: for every claim, trace it end-to-end. For every surface, find every occurrence and assign it a role. Make sure the model didn't miss surfaces. Find sibling paths the model should also worry about.

### Trace each claim

Producer → storage/transport → consumer → user-visible effect (operator-visible effect for backend/infra). One trace block per claim. `gaps` is allowed but must name the segment, not be silent. For UI claims, replace `transport` with `state` and `effect` with `render`.

### Search & classify every hit

For each surface in `model.md`:

1. Search using **`grep_terms`** from the surface record. Do not search `old_form`/`new_form` as literal strings — they are labels. Include serialization variants (camelCase ↔ snake_case, route slugs, db column variants) in the search.
2. Classify every non-generated hit into a role: `producer`, `consumer`, `transformer`, `serializer`, `storage`, `migration`, `validation`, `permission`, `cache`, `ui-render`, `test`, `doc`, `generated`, `irrelevant`.
3. **Fully read every hit in high-risk roles:** producer, transformer, serializer, storage, migration, validation, permission, cache, and any role touching async state or a public API boundary.
4. For mechanically similar hits, batch with `kind=batch count=N pattern=<...> role=<...> rationale=<why batching is safe>`. Do not silently sample.

The search closure rule: *"every occurrence is accounted for, but not every occurrence is deeply read."* Every hit has a role and a status. No `unclassified`, no silent skips.

### Completeness audit

Spawn the completeness-audit subagent per the trigger conditions in the Subagent policy section above. The subagent's inputs and prompt vary by target type:

- **Diff-based targets (`pr`, `branch`, `commit`, `uncommitted`):** subagent receives `$DIR/scope.md`, `$DIR/diff.patch`, and the current `model.md`. Instruction: *"independently derive every semantic surface the diff touches; report only what is missing from `model.md` or what looks misclassified; output structured bullets in the same format; do not propose findings; do not edit any file."*
- **`paths` target:** subagent receives `$DIR/scope.md`, `$DIR/inputs/` (the captured file contents), and the current `model.md`. Instruction: *"independently derive the public semantic surfaces (exports, configs, schemas, etc.) of these files; report what is missing from `model.md` or misclassified; do not propose findings; do not edit any file."*
- **`snippet` target:** **skip the completeness audit.** A snippet has no surrounding repo context — re-deriving "every surface the change touches" is not meaningful. Record `[A0] skipped=true reason=snippet-target-no-repo-context` in `search.md` and add a coverage caveat: *"Completeness audit skipped — snippet target lacks repo context to independently re-derive surfaces."*

For each audit entry: record the subagent's output, then write a main-thread disposition (`added-to-surfaces`, `rejected reason=...`, or `confirmed-complete`).

**Return loop (mandatory):** if `disposition=added-to-surfaces`, then before this phase completes:

1. Append the new surface to `model.md`.
2. **Return to the Model phase** for the new surface: state the implied claim (a surface without a claim is just a noun), append it to `model.md`, and re-run the ADR/spec drift sweep narrowly for the new surface's concept terms.
3. **Return to the trace step** above for the new claim.
4. Re-run the search-and-classify step for the new surface.

Skipping these steps means the new surface never gets falsified in the next phase — that's not optional.

### Sibling-path inspection

Spawn the sibling-discovery subagent (always run when the subagent policy permits — it's cheap; output is candidates not conclusions). Subagent receives `$DIR/model.md` and `$DIR/scope.md`, with the instruction *"for each changed file or claim, list candidate sibling implementations — the other side of a workflow (create/edit, single/bulk, admin/user, mobile/desktop, success/error/loading/empty, initial/retry/cancel, deletion-mirror), or alternate implementations of the same concept. Output paths with one-sentence rationale. Do NOT decide whether each sibling is broken."*

For each claim, record axes inspected: `create_vs_edit`, `single_vs_bulk`, `admin_vs_user`, `mobile_vs_desktop`, `success_vs_error`, `success_vs_loading`, `success_vs_empty`, `initial_vs_retry`, `initial_vs_cancel`, `deletion_mirror`. Each axis has a status (`inspected-both`, `only-<side>`, `N/A reason=...`). `N/A` without reason is forbidden.

Before processing sibling output, read `reference/bug-patterns.md` sections **3, 5, 6, 10** (sibling and parity heuristics).

**Write `$DIR/search.md`** per `artifact-schema.md` — sections for traces, hits, completeness audit, siblings.

**Gate:** every claim has a trace block. Every hit has a role and status. Every surface either has hits or carries a closure plan. Every claim has a sibling block with every axis status. Audit dispositions are complete. Return loops fully executed. No forbidden marker values.

---

## Falsification phase

Goal: for every claim, generate ≥3 concrete falsification attempts and read the code that proves or disproves each. Apply specific sub-checks for failure-state parity, backward compatibility, async invalidation, and deletion orphans.

Before starting, read `reference/bug-patterns.md` sections **4, 7, 8, 11, 13, 14, 15** (edge enumeration heuristics) and `reference/claude-failure-modes.md` in full.

`falsification.md` is the **unified candidate-findings store**. Candidates can originate from three places:

1. **Falsifications** — the per-claim falsification attempts below (this is the bulk).
2. **Source-of-truth conflicts** — any `model.md` source record with `kind=conflict` and `summary=unresolved` (or where a `potential_drift=<ADR-id>` was recorded) becomes a candidate here. Create an Fa record with `kind=source-conflict`; the "claim being falsified" is the resolution implied by the chosen authority.
3. **Test-derived defects** — written into `falsification.md` by the later Tests phase via the explicit step in that phase. Create with `kind=test-derived`.

Every candidate that could become a finding lives in `falsification.md` with an `Fa` ID. The Verification phase iterates over the complete set — anything not in `falsification.md` cannot become a finding.

**Per claim, ≥3 falsifications** covering:

- **Generic:** what input, state, or sequence makes the promise false?
- **Failure-state parity:** does this work on error / loading / empty / cancel / retry / timeout / permission-denied / partial-success paths? Untested paths are usually wrong.
- **Backward compatibility:** old data still in the database, old clients calling the API, old configs/feature flags, old enum values in persisted state, old URLs in shared links, cached state from before the change, persisted UI state (filters, selections, scroll positions).
- **Async invalidation:** for every async operation introduced or changed, what cancels in-flight work when state changes? Not just replacement requests — clearing, navigation, blur, filter change, identity switch.
- **Deletion orphans:** for every deletion-claim, what still references the removed thing — docs, metrics, configs, flags, monitoring, tests, generated code?

**If trailing focus text was given,** add ≥3 additional falsification attempts specifically targeting the focus area. The focus directive does not narrow scope — broad falsifications still run.

Each falsification has a `result`: `disproved`, `reachable-defect`, or `inconclusive`. `inconclusive` is permitted transiently but must resolve to `reachable-defect` or `disproved` before the Verification phase ends.

**Write `$DIR/falsification.md`** per `artifact-schema.md` — one block per claim with falsifications and the four sub-checks (`backward_compat`, `failure_parity`, `async_invalidation`, `deletion_orphans`).

**Gate:** every claim has ≥3 falsifications OR an explicit written reason for fewer (`reason=claim has only one observable behavior`). The four sub-checks are each addressed (findings, "checked: no issue", or `N/A reason=...`). No silent skips. No forbidden marker values.

---

## Tests phase

Goal: read touched tests as artifacts to audit, not as proof. Ask what the fixture makes impossible.

For every test file touched by the diff or covering surfaces in `model.md`:

- **Fixture blindness:** what does the fixture make impossible to fail? (perfect data, mocked services, single-user assumption, no concurrency, no old data, same fake ID reused across distinct semantic types, etc.)
- **Assertion audit:** does the assertion encode the regression? Does it assert the wrong thing?
- **Coverage gaps:** which `reachable-defect` candidates from `falsification.md` does this test not cover?
- **New tests added:** `yes` / `no` / `missing-but-recommended`.

Coverage gaps that cover a `reachable-defect` from `falsification.md` are themselves candidate findings (severity scaled to the underlying defect). **Append them as Fa records to `falsification.md`** with `kind=test-derived`, citing the test file:line and the underlying `Fa` ID. This keeps the unified candidate-store invariant: every candidate that could become a finding lives in `falsification.md` and is iterated by the Verification phase.

If the Tests phase reveals a fixture-blindness defect that is **not** already represented by a falsification (e.g. an existing test "passes" but the fixture makes the real failure impossible to surface), also append a `kind=test-derived` Fa record with the underlying defect described.

**Write `$DIR/tests.md`** per `artifact-schema.md`. Append `kind=test-derived` records to `$DIR/falsification.md` for any test-revealed candidates.

**Gate:** every touched test file has a block. Coverage gaps are linked back to specific `falsification.md` IDs (existing or newly appended). No forbidden marker values.

---

## Verification phase

Goal: turn `reachable-defect` candidates into verified findings; drop the rest. The verification gate is the hard invariant — only verified findings reach the Review phase.

### Main-thread literal re-read

For every candidate with `result=reachable-defect`:

1. Re-open the primary cited file at the cited line with 30–80 lines of context (more if the change touches a long async block or multi-step handler).
2. Re-open every supporting file the candidate depends on: producer, consumer, sibling, test, source-of-truth doc — whichever links the claim relies on.
3. Ask: **can I state, in one sentence each, the condition, the actual wrong behavior, and the concrete impact, with every link in the chain confirmed by the code I just read?**

If the re-read reveals a guard you missed:

- Guard fully prevents the failure → drop with reason.
- Guard narrows the condition → rewrite the candidate with the narrower condition. **Return loop:** re-check the falsification block for whether the narrowed condition changes severity, related sites, or test gaps. Update accordingly.
- Guard makes the path less common but still reachable → keep, possibly lower severity.

Do not preserve a candidate's framing once contradictory context appears. Attached reviewers become untrustworthy.

### Adversarial verification (subagent)

Run on **every** Critical and High candidate, and on every Medium candidate that is cross-file or race-condition. Skip for purely local Low/Medium candidates.

Spawn a subagent (`subagent_type: general-purpose`) with **only**:

- The candidate's bullet from `falsification.md` (after the re-read updates).
- The cited file:line for each link in the chain.
- Instruction: *"You are an adversarial verifier. Read only the cited locations and their surroundings. Try to disprove this finding. Return one of: `holds <reason>`, `disproved <reason and citation>`, `narrows <revised condition>`, `unsupported <what evidence is missing>`. Do not extend the search; do not propose new findings."*

(`Explore` is wrong for this — adversarial verification is bounded code reasoning, not file-location.)

Verdict handling:

- `holds` → keep finding.
- `disproved` → drop with verifier's reason.
- `narrows` → rewrite finding with narrower condition; re-run the "guard found" decision tree above and the return-loop to the falsification block.
- `unsupported` → return to the re-read step with the verifier's suggestion; if you still cannot supply the missing evidence, drop the finding.

### Promote and drop

Surviving candidates become verified findings (each with severity, headline, primary site, condition, behavior, mechanism, impact, fix direction, optional related sites, root-cause-group label, verifier verdict). Dropped candidates are recorded with one-line reasons (`guard-found`, `disproved-by-verifier`, `unsupported`, `superseded-by-finding-Fn`).

**Write `$DIR/verification.md`** per `artifact-schema.md` — two sections: `## Verified findings` (`[F1]` records) and `## Dropped candidates` (`[D1]` records).

**Gate before Review phase:** every candidate from `falsification.md` is in `verification.md` as either verified or dropped. No `inconclusive` remains. Every verified finding has all fields. Every Critical/High has `verifier_verdict` of `holds` or `narrows`. No forbidden marker values.

---

## Review phase

Goal: emit a single rendered review that reads as one reviewer's output and is verified at every cited line.

Read `reference/output-format.md` and `reference/claude-failure-modes.md` before drafting.

### Hard invariant

**A finding appears in `review.md` if and only if it appears in `verification.md` with `verifier_verdict=holds` or `verifier_verdict=narrows` (or `verifier_verdict=skipped-local` for purely local Low/Medium).** Everything else is dropped, an open question, residual risk, or a test gap.

### Failure-mode preflight (internal, before printing)

Answer these eleven yes/no questions silently. **Any "no" returns the review to the named phase.**

1. (Model) Did I read CLAUDE.md / AGENTS.md / ADRs, run the ADR drift sweep, and record source-of-truth conflicts?
2. (Search) Did I extend past changed lines into producers, consumers, and downstream effects?
3. (Tests) Did I read touched tests as artifacts — fixture blindness, assertion correctness, coverage gaps — rather than as proof?
4. (Falsification) Did I treat refactor-claims as falsifiable and look for behavioral drift (query enablement, side effects, error rendering, memoization) rather than "compiles + tests pass"?
5. (Search) Did I enumerate sibling axes (create/edit, single/bulk, admin/user, mobile/desktop, success/error/loading/empty, initial/retry/cancel, deletion-mirror) for every claim?
6. (Falsification) Did I check error / loading / empty / cancel / retry / timeout / permission-denied / partial-success paths, not only happy paths?
7. (Search) Did I search both producers AND consumers of every changed surface, with classification of every hit?
8. (Verification) Did I drop every unverified suspicion instead of hedging it into findings?
9. (Falsification) Did I check async invalidation — every event that should cancel in-flight work, not just replacement requests?
10. (Search + Falsification) Did I separate UI gating from server-side authorization for every permission-touching change?
11. (Falsification) Did I check backward compatibility against old data / old clients / old configs / old enums / cached state / persisted UI state?

### Output structure

Printed to chat AND written to `$DIR/review.md`:

```
# Custom Review — <target description, one line>

<short two-line summary: target, base, scope, focus directive if any>

## Findings

<grouped by severity, then root_cause_group; same-cause findings collapsed into one entry with multiple related_sites>

### Critical
<rendered findings>

### High
...

### Medium
...

### Low
...
(omit any severity heading entirely when zero findings in that band)

## Open questions

<uncertain high-risk issues that could not be fully verified — bullet list with file:line and what would resolve the uncertainty. The safety valve so "no hedging" does not become false certainty.>

## Coverage

- **Files inspected:** <count> (<key paths or directory groups>)
- **Commands run:** <git diff / rg / tests / typecheck / lint commands and results>
- **Subagents used:** <which subagents ran and what they returned>
- **Not checked:** <out-of-scope, with reason>
- **Residual risk:** <what this review didn't close>
- **Test gaps:** <missing coverage that matters>
```

### Per-finding rendering

```
**[Severity] path/to/file.ext:LINE — short headline**

When <condition>, this code does <wrong behavior> because <mechanism>, causing <impact>.

Fix direction: <one sentence>.

Related sites: file:LINE, file:LINE.   (omit if none)
```

### Hard output rules

- **Order by severity, then by root-cause group.** Same-cause findings collapse to one entry with multiple `related_sites`. Never order by file.
- **ADR / spec / doc deviations are first-class findings** even if the code runs.
- **No hedging** (`maybe`, `seems`, `possibly`, `might`, `appears to`). Uncertain high-risk → Open Questions, not findings.
- **No confidence labels.** A finding is reported or it isn't.
- **No process narration**, no attribution, no praise filler, no time-spent mentions.
- **Skip list applies:** pure style, *"consider X"* without bug, generic architecture, restating diff, low-confidence guesses, unmotivated test requests, speculative rewrites, *"feels risky"* without proof.
- **Finding minimality.** Keep highest-signal items; move weak/low uncertainties to Residual Risk in coverage. Five clearly-actionable findings beat ten diluted ones.
- **Zero findings:** state it explicitly. Do not pad to look productive. Coverage + Residual Risk + Test Gaps still printed.

---

## Reference files

Mandatory reads at specific points, not optional context.

| File | Read when | Purpose |
|---|---|---|
| `reference/artifact-schema.md` | Before any artifact is written | Per-phase artifact templates and ID prefixes. |
| `reference/bug-patterns.md` | Selected sections at Model, Search, Falsification phases | 15 heuristics priming attention to bug classes. |
| `reference/claude-failure-modes.md` | Falsification and Review phases | 11 archetypes of reviews that miss bugs. |
| `reference/output-format.md` | Review phase | Severity, finding shape, coverage footer, skip list, zero-findings rule. |

---

## Failure modes — quick refusal table

| Failure | Action |
|---|---|
| Not in git AND no paths/snippet given | Refuse; ask operator for paths. |
| Empty diff (git target) | Refuse with `nothing to review`. |
| PR target — `<head_ref>` not present locally | Fetch read-only: `git fetch origin pull/<num>/head:refs/custom-review/pr-<num>`. Do not abort, do not checkout. |
| Target ambiguous | Ask one short multi-choice question. |
| Operator passed `-` as trailing text | Ignore. |
| `gh` unavailable for PR target | Refuse. Without `gh pr view`, head/base ref names cannot be resolved reliably. Ask the operator for explicit head/base (e.g. `/custom-review against <base>` from a branch that tracks the PR head) and proceed as a `branch` target. |
| `tmp/` writes denied | Refuse — review cannot run without artifacts. |
| `paths` target — listed paths do not exist | Refuse; list missing paths. |
