---
name: multi-review
description: Review a target with claude `/custom-review` always, plus codex `/review` when the change is significant enough to justify codex's limited budget. By default multi-review auto-decides whether to run codex from the change's significance and the review round; the caller can force it with `--codex` / `--no-codex`. Saves verbatim reviewer outputs to `tmp/multi-review/`, synthesizes a merged best-of review, optionally applies the fixes, and — only when codex also ran — writes an A/B evaluation comparing the two reviewers on accuracy, signal-to-noise, and depth (this powers iterative improvement of the review skills). Codex runs as a plain `/review` with only the target; non-target trailing text after `/multi-review` is forwarded verbatim to the claude reviewer as additional focus.
---

# Multi Review

## Purpose

`/multi-review` reviews a target with claude `/custom-review` — always — and, **when warranted**, codex `/review` alongside it, then synthesizes a merged best-of review. Every run emits a **gate verdict** — the pre-fix critical count, `pass` iff zero — which is the skill's primary machine-readable output and is computed from the merged review independent of whether codex ran (see Step 5). When both reviewers ran, the skill *additionally* writes an evaluation comparing them so the user can A/B-test the review skills and improve them over time. The gate is the verdict (always present); the evaluation is the codex-only analysis.

**Repo-local conformance reviewer (generic extension point).** This is a documented plug, not a
reference to any one project: **any** repository may opt in by defining a skill at
`.claude/skills/gate-check/SKILL.md` that supports a review mode taking the same target arg and
returning a findings report. When that file exists at the repo root, it runs as a third reviewer
on a different axis — repo-convention conformance (e.g. ADR/spec violations, stale living docs,
size budgets) rather than correctness — and is otherwise inert: a repo without it is **wholly
unaffected** and the skill never mentions it. The coupling is exactly the slug + path + the
review-mode/report shape below; no repo specifics live in this skill. It always runs when present
(no budget gate), its findings merge like any reviewer's and so its criticals count toward the
gate verdict, but it is **excluded from the codex A/B evaluation** (different axis, nothing to
compare).

**Codex is selective by design.** Codex is the higher-signal reviewer — it routinely catches issues the others miss — but its usage budget is far lower and is easily exhausted. So codex runs only when the change is worth that budget: a fundamental/critical change with far-reaching effects, or one with enough technical subtlety to be easy to get wrong. It should *not* burn budget on mechanical, doc, config, or UI changes, or on routine re-review rounds where a slip is low-stakes. That decision is made by the **codex gate** in Step 2.5 — auto-decided by default, or forced by the caller with `--codex` / `--no-codex`. The 99% path is an agent invoking `/multi-review` and letting the gate decide; centralizing the logic here (rather than in every caller) is deliberate, so it can be tuned in one place.

Key difference from `/codex-review`: this skill is **invoked fresh** (not after a prior `/review`). The target must be determined from `/multi-review` arguments, not from earlier conversation context.

## Hard preconditions

Refuse with a clear, short message if any fail:

1. **Working directory is inside a git repository.** Both reviewers operate on a working tree.
2. **`codex` is on `PATH`** — *only required when codex will actually run.* Run `command -v codex`. If missing: when the caller passed `--codex` (an explicit request for codex), refuse and tell the operator to install codex; otherwise do **not** refuse — record that codex is unavailable and let the codex gate (Step 2.5) force `run_codex = false` with a note. The skill stays useful with `custom-review` alone.
3. **The `custom-review` skill is available.** If it is missing from the available-skills list, refuse.
4. **`gh` is on `PATH` and authenticated** — *only* if the target is `pr`. Run `command -v gh` and `gh auth status`. If either fails, refuse with the missing piece.

## Step 1 — Parse args and determine target

Split `/multi-review`'s trailing text into three buckets:

- **Target hints** — phrases that explicitly identify what to review (see table below).
- **Control flags** — recognized control tokens that change skill behavior, not forwarded as focus text. Recognized:
  - `--auto-apply` — run non-interactively, for programmatic callers (another skill or subagent where no human is present to answer prompts). It skips **every** interactive prompt this skill would otherwise raise: (1) the Step 5 "Apply these fixes now?" prompt — proceed straight to Step 6 (apply fixes); and (2) the Step 2 collision prompt — overwrite any existing output files for the slug instead of asking. The evaluation is still written in Step 8 (if codex ran). **`--auto-apply` does not influence the codex gate** — it governs prompts only, not whether codex runs.
  - `--codex` — force codex to run regardless of the Step 2.5 auto-decision. Use when the caller has already judged the change worth codex's budget.
  - `--no-codex` — force codex to be skipped regardless of the auto-decision. `custom-review` still runs.
  - Passing both `--codex` and `--no-codex` is contradictory — refuse with a one-line message.
- **Focus text** — everything that doesn't match a target hint or control flag; forwarded verbatim to the claude reviewer (custom-review) as additional focus. Codex is not given focus text — it runs as a plain `/review` with only the target flags. (Focus text still informs the codex gate's read of the change — see Step 2.5.)

Parse control flags by splitting the trailing text on whitespace and removing any token that matches a recognized flag (`--auto-apply`, `--codex`, `--no-codex`) before computing target hints and focus text. Record the set of flags encountered for later steps.

Target heuristics (parse from args; default to uncommitted):

| Args contain | Target type | Notes |
|---|---|---|
| `PR #N`, `#N`, or a GitHub PR URL | `pr` | Extract `N`. |
| `against X` or `vs X` | `branch` | Current branch reviewed against base `X`. |
| A 7+ hex SHA | `commit` | Use as commit ref. |
| `uncommitted` or `working tree` | `uncommitted` | |
| Nothing target-like | `uncommitted` | Default. |

**Removed shorthands** (do not silently accept them):

- `branch X` — ambiguous between "review branch X" and "review current against X". Reject with a clear correction: "Did you mean `against X`?"
- `staged` — would silently include unstaged changes too. Reject with a correction: "use `uncommitted` (covers staged + unstaged + untracked) or commit your staged changes first."

If args are ambiguous (e.g., both a PR and a base named), ask one short multiple-choice question.

### PR preflight (target = `pr` only)

1. `gh pr view <N> --json headRefName,baseRefName,headRefOid` to fetch refs and OID.
2. `git rev-parse --abbrev-ref HEAD` → current branch. If it doesn't match `headRefName`, abort: "PR head branch is `<headRefName>` but you're on `<currentBranch>`. Run `gh pr checkout <N>` and re-invoke."
3. `git rev-parse HEAD` → current local OID. Compare to `headRefOid`:
   - **Equal** → proceed.
   - **Local ahead** (PR head is an ancestor of HEAD): abort with `git push` guidance — codex would review your local commits but `custom-review` resolves the GitHub PR head, so the two reviewers would see different code.
   - **Local behind** (HEAD is an ancestor of PR head): abort with `git fetch origin pull/<N>/head && git reset --hard FETCH_HEAD` guidance (or `gh pr checkout <N>`).
   - **Diverged**: abort with a "force-push or rebase to align" message; do not auto-resolve.
4. Reject dirty worktree for `pr` targets: if `git status --porcelain` is non-empty, abort with "commit, stash, or discard before /multi-review on a PR" (the reviewers operate on different snapshots, so worktree drift breaks comparability).

### Empty-diff preflight

Before spawning anything, verify the target has a non-empty diff:

| Target | Check |
|---|---|
| `pr` | `git diff <baseRefName>...<headRefName> --stat` non-empty (after the PR fetch in custom-review's lookup). For the preflight, `gh pr diff <N> --name-only` is enough. |
| `branch` | `git diff <X>...HEAD --name-only` non-empty. |
| `commit` | `git show --stat <sha>` shows file changes. |
| `uncommitted` | `git status --porcelain` non-empty. |

If empty, refuse: "Target `<phrase>` has no changes to review."

### Target strings (used downstream)

Build two distinct strings — do not collapse them:

- **Display phrase** (printed to the operator):
  - `pr` → `PR #<N>`
  - `branch` → `branch <currentBranch> against <X>`
  - `commit` → `commit <sha>`
  - `uncommitted` → `the uncommitted changes in the working tree`
- **Canonical reviewer arg** (passed verbatim to the subagent invoking custom-review; its resolution table parses this):
  - `pr` → `<N>`
  - `branch` → `against <X>`
  - `commit` → `<sha>`
  - `uncommitted` → `uncommitted`

Also record `<base branch>` (PR's `baseRefName` or the `X` from `against X`) for codex's `--base` flag.

## Step 2 — Derive slug and check for collision

Derive a slug from the target:

| Target | Slug |
|---|---|
| `pr` | `pr<N>` (e.g., `pr100`) |
| `branch` | `branch-<sanitized-name>-<hash>` where `<hash>` is the first 6 chars of `sha1sum` of the raw branch name. Sanitization: lowercase, non-alphanumeric → `-`. The hash disambiguates `feature/a` from `feature-a`. |
| `commit` | `commit-<short-sha>` (first 7 chars) |
| `uncommitted` | `uncommitted-<hash>` where `<hash>` is the first 6 chars of `sha1sum` of `git status --porcelain` + `git diff` output — disambiguates back-to-back runs on different working states |

Output paths (project-local `tmp/`):

- `tmp/multi-review/codex-<slug>.md`
- `tmp/multi-review/custom-review-<slug>.md`
- `tmp/multi-review/merged-<slug>.md`
- `tmp/multi-review/evaluation-<slug>.md`

Plus per-reviewer status sidecars (see Step 3):

- `tmp/multi-review/codex-<slug>.status.json`
- `tmp/multi-review/custom-review-<slug>.status.json`

**Collision check.** Before running anything, check if any of these files already exist.

- **Interactive (no `--auto-apply`):** if any exist, warn the operator listing which files exist, and ask via `AskUserQuestion` whether to overwrite. Exit on "no".
- **`--auto-apply` passed:** do **not** prompt — there is no human to answer, and a prompt here would stall an autonomous multi-round loop. The slug is stable across rounds (`pr<N>`, or `branch-<name>-<hash>` hashed from the branch *name*, not the diff), so round 2+ always collides with round 1's files. Overwrite the existing outputs, printing a one-line notice naming the slug being overwritten.

Then `mkdir -p tmp/multi-review/`.

## Step 2.5 — Codex gate: decide whether codex runs

`custom-review` always runs. This step decides a single boolean, `run_codex`, that governs whether codex `/review` runs alongside it. Resolve it in **precedence order** — the first matching rule wins:

1. **Explicit override (caller's conscious decision).**
   - `--codex` → `run_codex = true`.
   - `--no-codex` → `run_codex = false`.
   - (Both flags together were already refused in Step 1.)

   An explicit flag is honored verbatim — do **not** second-guess it with the auto-decision. This is the escape hatch for a caller who has already made the judgment.

2. **Auto-decision (no explicit flag — the 99% path).** Take a quick look at *what is actually being reviewed* and *which round this is*, then decide. The two gates compose: the round gate runs first and can short-circuit to skip; the change-nature gate decides the rest.

   **(a) Round gate.** Determine the round from whether prior output artifacts for this slug already exist in `tmp/multi-review/` (you already learned this in the Step 2 collision check):
   - **Round 1** (no prior artifacts) → fall through to the change-nature gate (b).
   - **Round ≥ 2** (prior artifacts exist) → **default `run_codex = false`.** A follow-up pass after fixes is usually lower-stakes, and codex makes less and less sense each round. Re-enable codex (`true`) only if **either**:
     - the **prior round surfaced a critical/blocking finding** — read the prior `merged-<slug>.md` (and `codex-<slug>.md` if present); if it contained ≥1 blocking-severity finding, trust is eroded enough to keep codex in the loop; **or**
     - the **current change is itself high-risk/subtle** by the change-nature gate (b) — a fix that is easy to get wrong justifies another codex pass even on a re-review.

     Otherwise stay skipped. (Round detection is best-effort: the `uncommitted` slug embeds a diff hash, so back-to-back uncommitted runs each look like round 1 — that errs toward *including* codex, which is the safe direction. `branch`/`pr`/`commit` slugs are stable across rounds and detect re-review correctly.)

   **(b) Change-nature gate.** Look at the actual diff — paths, content, and breadth (use the diff you already have from the empty-diff preflight, or a fresh `git diff --stat` plus a skim of the substantive hunks):
   - **Lean skip** — the diff is dominated by low-stakes change where a slip is cheap: docs / markdown / comments, formatting / lint-only, pure renames, config / lockfile / dependency bumps, generated code, mechanical test churn, or isolated UI / styling.
   - **Lean include** — the diff touches subtle or far-reaching surface: core engine / protocol / parsing logic, security / auth / crypto, concurrency / async-cancellation / ordering / locking, data flow across layers (producer → storage → transport → render), state machines, error / edge-case handling, or a wide blast radius (many subsystems, or many files of real logic). Operator focus text that flags subtlety or "easy to get wrong" is itself a strong include signal.
   - **Borderline** (genuinely mixed or unclear) → resolve by round: **round 1 → include** (cheap insurance on the first look), **round ≥ 2 → skip** (we already had a pass). This asymmetry is intentional.

3. **Availability cap.** After the rules above, if `run_codex` is `true` but `codex` is not on `PATH` (precondition 2), force `run_codex = false` and note "codex unavailable on PATH". (An explicit `--codex` with codex absent already refused in precondition 2, so this cap only ever silently downgrades an *auto* decision.)

**Announce the decision.** Print exactly one line so every gate decision is auditable and the heuristic stays tunable from the evaluation data:

```
codex: <included|skipped> — round <N>, <one-clause reason>
```

Examples: `codex: skipped — round 1, docs/markdown-only diff`; `codex: included — round 1, touches engine proxy + async cancellation`; `codex: skipped — round 2, prior round had 0 blocking findings`; `codex: included — round 2, prior round had blocking findings (trust check)`; `codex: included — forced by --codex`.

Carry `run_codex` (and the announced reason) into the steps below.

## Step 3 — Spawn the enabled reviewers

If `run_codex` is true, both reviewers start in a **single message** with two tool calls so they run concurrently. If `run_codex` is false, **skip Reviewer A entirely** and spawn only Reviewer B (the foreground `custom-review` Agent) — there is no codex Bash call, no `codex-<slug>.*` files, and no background process to monitor.

Additionally, if `.claude/skills/gate-check/SKILL.md` exists at the repo root, spawn Reviewer C
in the **same message** as the other enabled reviewer(s) so they all run concurrently. Check for
that file before composing the spawn message (a single `test -f`); if it is absent, there is no
Reviewer C and nothing about gate-check is printed.

### Reviewer A — codex (background Bash) — *only if `run_codex` is true*

Skip this entire subsection when the Step 2.5 gate set `run_codex = false`.

Run a plain `codex review` with only the target flags — **no custom prompt, no AGENTS.md preamble, no focus text**. Codex sees the same invocation it would see from a bare `/review` against this target. Flags by target:

| Target | Flags |
|---|---|
| `pr` | `--base <baseRefName>` |
| `branch` | `--base <baseBranch>` |
| `commit` | `--commit <sha>` |
| `uncommitted` | `--uncommitted` |

Run codex with a single background Bash call (run_in_background: true, timeout 600000 ms):

```sh
flags=(<each flag and its value as a separate array element, e.g. "--base" "main">);
codex review "${flags[@]}" > tmp/multi-review/codex-<slug>.md 2> tmp/multi-review/codex-<slug>.stderr;
rc=$?;
printf '{"reviewer":"codex","exit":%d,"timed_out":false,"output":"tmp/multi-review/codex-<slug>.md"}\n' "$rc" > tmp/multi-review/codex-<slug>.status.json;
```

The trailing `;` per CLAUDE.md guards against the sandbox pipe-drop bug. Keep stderr separate so the output file stays parseable as a review.

**Empty-output guard.** After codex finishes, before treating its output as a review, the parent must check: if `exit != 0` or `stat -c %s tmp/multi-review/codex-<slug>.md` reports `0`, mark the status sidecar as `"ok": false` with a reason that includes the exit code and a pointer to the `.stderr` file. The codex CLI prints argument errors to stderr and exits without writing anything to stdout, so a silent zero-byte review file is the failure shape to defend against.

### Reviewer B — claude `/custom-review` (Agent tool, foreground)

Spawn a general-purpose Agent. Crucial constraint: `custom-review` **will not** write outside its own `tmp/custom-review-<timestamp>/review.md` (see custom-review/SKILL.md:16,20). Instructing the subagent to write elsewhere will either fail or violate the skill. So the parent collects the review path from the subagent and copies it after.

Sample prompt (fill in concrete values):

> You are running a code review as part of a multi-reviewer comparison. Do not infer the target from this prompt's framing — the target is given below.
>
> **Target (canonical arg for the custom-review skill):** `<canonical reviewer arg>`
> **Display phrase (for human reference only):** \<display phrase\>
> **Additional focus from operator:** \<focus text, or "(none)"\>
>
> Invoke the `custom-review` skill via the Skill tool, passing the canonical arg above as its target. If the operator provided additional focus text, forward it verbatim as part of the skill's invocation.
>
> Let the skill write to its standard `tmp/custom-review-<timestamp>/` directory — **do not** redirect or override that path. When the skill finishes, your reply to me must be exactly two lines:
>
> ```
> REVIEW_PATH=<absolute path to the review.md the skill wrote>
> FINDINGS=<integer count of distinct findings in that review>
> ```
>
> If the skill refuses or fails, reply with a single line: `FAILED: <one-sentence reason>`. Do not paraphrase or echo the review body in your reply.

### Reviewer C — repo-local gate-check (Agent tool, foreground) — *only if the repo defines it*

Skip this subsection entirely when `.claude/skills/gate-check/SKILL.md` does not exist at the repo
root. The not-defined case is the common one and is **silent** — printing "no gate-check here" on
every run in every repo that hasn't opted in would be noise, and the decoupling guarantee is that
such repos are wholly unaffected.

When the repo *does* define it, **announce gate-check's status in one line** once it returns
(mirrors the codex one-liner), so a defined-but-failed conformance reviewer is never silent —
fail-open must not mean fail-quiet:

```
gate-check: <ran N findings (C critical) | failed — <reason>>
```

Spawn a general-purpose Agent in the same message as the other reviewer(s):

> You are running a repo-conformance review as part of a multi-reviewer pass. Read
> `.claude/skills/gate-check/SKILL.md` at the repo root and execute that skill exactly as
> written, in review mode, on the target: `<canonical reviewer arg>`. Follow its workflow,
> reference files, mandated commands, and output format; let it write its report under its
> standard `tmp/gate-check-<ts>/` path. When it finishes, reply with exactly three lines:
>
> ```
> REPORT_PATH=<absolute path to the report.md it wrote>
> FINDINGS=<integer count of findings>
> CRITICALS=<integer count of Critical findings>
> ```
>
> If the skill refuses or fails, reply with a single line: `FAILED: <one-sentence reason>`.

### Why one Bash + one Agent in one message

(Applies when `run_codex` is true.) Both are independent; issuing them in a single message starts them in parallel. Codex runs in background because its 10-min timeout is longer than the Agent typically takes; the custom-review Agent is foreground (its result returns when complete). After this message, monitor for the background codex completion before proceeding.

When `run_codex` is false there is only the foreground custom-review Agent — issue it alone and wait for its result; there is no background process to monitor.

## Step 3.5 — Collect outputs into the canonical paths

After the enabled reviewer(s) finish, normalize their outputs so Step 4 can read predictable paths.

**Reviewer B (`custom-review`):**

1. Parse Reviewer B's reply for `REVIEW_PATH=<...>`. If parsing fails or the file does not exist, treat as failure.
2. On success: `Read` the source file (the skill writes it under its own `tmp/custom-review-<timestamp>/` directory), then `Write` its full contents to `tmp/multi-review/custom-review-<slug>.md`. Use `Read` + `Write` rather than a shell `cp` so the file goes through normal write paths.
3. Write `tmp/multi-review/custom-review-<slug>.status.json`:
   ```json
   {"reviewer":"custom-review","ok":true,"source":"<REVIEW_PATH from B>","findings":<N>,"output":"tmp/multi-review/custom-review-<slug>.md"}
   ```
4. On failure: write a placeholder `tmp/multi-review/custom-review-<slug>.md` containing exactly `FAILED: <reason>` and a status sidecar with `"ok":false,"reason":"<reason>"`.

**Reviewer C (gate-check), when it ran:** same collection pattern as Reviewer B — parse
`REPORT_PATH=`, copy the report to `tmp/multi-review/gate-check-<slug>.md`, and write
`tmp/multi-review/gate-check-<slug>.status.json` with `findings` and `criticals` counts. On
failure, write the `FAILED: <reason>` placeholder and an `"ok":false` sidecar; a failed
gate-check never aborts the run (custom-review remains the load-bearing reviewer).

**Post-write sanity check.** Before proceeding to Step 4, confirm that `tmp/multi-review/custom-review-<slug>.md` and (if codex ran) `tmp/multi-review/codex-<slug>.md` exist as distinct files.

For codex (Reviewer A):

- **Gate-skipped (`run_codex = false`):** no codex output or sidecar was produced. Write a sidecar that records the *skip* (distinct from a failure) so later steps can tell them apart:
  ```json
  {"reviewer":"codex","ok":false,"skipped":true,"reason":"codex gate: <reason from Step 2.5>"}
  ```
- **Ran (`run_codex = true`):** the status sidecar was already written by the bash command. If `exit != 0` or the output file is empty (`stat -c %s ... -eq 0`), update its status to `"ok":false` (a genuine failure, not a skip) and leave the output file as-is (codex's own error messages are useful evidence).

**Abort condition.** Abort only when **no reviewer produced a usable review** — i.e. custom-review failed *and* codex either failed or was gate-skipped. In that case print the reason(s) and stop before merging. A gate-skipped codex is **not** a failure: with custom-review successful, proceed normally on the single review.

## Step 4 — Synthesize merged review

`Read` each available `tmp/multi-review/*-<slug>.md` output (skip any whose status sidecar is `"ok":false` — this includes a gate-skipped codex). Produce **one** merged review and write it to `tmp/multi-review/merged-<slug>.md`.

**Single-reviewer case (codex skipped or failed):** only custom-review's output is available. The merge degrades to a pass-through — still apply synthesis rule 2 (re-read each finding's cited code and keep only those you now believe are real), still group by severity, still single-voice. The consensus rule (1) is moot with one reviewer. A merged review is still produced because Step 6 applies fixes from it. (Gate-check, when it ran, is a second source even in this case — "single-reviewer" refers to the correctness axis; conformance findings still merge in.)

**Gate-check findings in the merge:** they enter the merged review like any reviewer's, with one
extra rule — preserve each finding's `binding-source:` citation (ADR / living doc / budget pin)
in the merged entry; that citation is what makes a conformance finding actionable. Synthesis
rule 2 (re-read before keeping) applies to them too.

Synthesis rules (same as `codex-review` Step 5):

1. **Findings flagged by 2+ reviewers** — keep, dedupe to one entry. Use the clearest wording. Note multi-reviewer agreement as `(consensus)` next to the heading — useful evidence for the evaluation step, not noise.
2. **Findings flagged by only one reviewer** — re-read the actual code with `Read`. Keep only if you now believe it's real. Drop hallucinations and noise.
3. **Disagreements** — pick the position you now believe correct after re-reading. Do not mark as "disputed".
4. **Voice** — single unified reviewer voice. No "codex said X / custom-review said Y" attribution in the body.
5. **Structure** — group by severity (blocking → medium → optional). File:line references on every finding.

**Only when codex ran** (`run_codex` was true and codex produced a usable review), also write `tmp/multi-review/provenance-<slug>.md` capturing, per finding (kept or dropped):

- Which reviewer(s) raised it.
- Kept / dropped / merged decision and one-line reason.

The evaluation step (Step 8) uses this directly; never lose it to in-memory state. When codex was skipped there is no A/B comparison to write, so the evaluation and its provenance are skipped entirely (see Step 8) — do **not** produce a provenance file in that case.

## Step 5 — Emit the gate verdict, print merged review, ask to fix

Print the full contents of `merged-<slug>.md` inline in the chat.

### Gate verdict (always emitted — codex-independent)

The **gate** is the pre-fix critical count, and it is the skill's primary machine-readable output: callers such as `plan-implement-merge` loop on it (review → fix → re-review) until it reads zero. The merged review always groups findings by severity (blocking → medium → optional) and is produced *before* any fixes (Step 6), so its blocking section **is** the pre-fix critical set — whether or not codex ran. Count it from the merged review and print exactly one line:

```
gate: <pass|fail> — <N> pre-fix critical finding(s) [reviewers: custom-review[+codex][+gate-check]]
```

`pass` iff `N == 0`. Treat any finding the merged review labels `blocking`, `critical`, or `P0` as critical (the merge groups under a `blocking` heading; the synonyms guard against drift). Because gate-check findings merge in like any reviewer's (Step 4), a critical **conformance** finding counts toward `N` and can fail the gate on its own — that is the point of running it in the cycle. List in the `reviewers:` tag only the reviewers that actually ran. This line is emitted on **every** run — codex included, gate-skipped, or `--no-codex` — so the no-criticals gate never depends on codex having run. It is distinct from the Step 8 evaluation (an A/B comparison that *is* codex-only); the gate is the verdict, the evaluation is the analysis.

Examples: `gate: pass — 0 pre-fix critical finding(s) [reviewers: custom-review]`; `gate: fail — 2 pre-fix critical finding(s) [reviewers: custom-review+codex]`; `gate: fail — 1 pre-fix critical finding(s) [reviewers: custom-review+gate-check]`.

### Apply prompt

**If `--auto-apply` was passed in the args**, skip the prompt entirely: set `fixes_applied=true`, print a one-line notice ("auto-apply: applying all merged findings without prompting"), and proceed to Step 6. The evaluation in Step 8 is still written *if codex ran*.

Otherwise, call `AskUserQuestion` with a yes/no:

- **Question:** "Apply these fixes now?"
- **Options:** "Yes — apply all merged findings" / "No — skip fixes (evaluation still written if codex ran)"

Regardless of the answer, an evaluation will be written in Step 8 *if codex ran* (skipped otherwise — see Step 8). The fix experience supplies grounded judgments; without it, evaluation fields that depend on fix evidence are explicitly marked `not assessed (fixes declined)` rather than guessed.

If "no": skip Steps 6 and 7, jump to Step 8 with the `fixes_applied=false` flag.

## Step 6 — Apply fixes (one pass, no per-finding checkpoint)

(Runs if either the operator answered "yes" in Step 5, or `--auto-apply` was passed.)

Apply every blocking and medium finding from the merged review in one pass. Optional/polish findings: apply if cheap, skip if invasive.

While fixing, keep brief notes for the evaluation step:

- Which findings were real, partial, or false alarms once you got into the code.
- Which findings required reading code the reviewer didn't cite (under-statement).
- Which findings exaggerated severity or impact (over-statement).
- Which findings were uniquely deep (would have been missed by the other reviewer).

Do not prompt the user between findings.

## Step 7 — Best-effort verification

(Only runs if Step 6 ran.)

If there is an obvious one-command quick check in the repo, run it and capture the result:

- Rust: `cargo check` (and `cargo test` if fast)
- Node/TS: `npm test`, `pnpm test`, or `yarn test`; or `npx tsc --noEmit`
- Python: `pytest -q` if a `pytest.ini`/`pyproject.toml` indicates it
- Go: `go build ./...`

If the project has no obvious quick check, or the check would take more than ~2 minutes, skip it. Note the result (or that it was skipped) in the evaluation.

Do **not** block the evaluation on a green check — the evaluation is about reviewer quality, not the final state of the code.

## Step 8 — Write evaluation (only when codex ran)

**Skip this entire step when codex did not run** (gate-skipped via Step 2.5, forced off with `--no-codex`, or failed). The evaluation is an **A/B comparison** of two reviewers — with only `custom-review`, there is nothing to compare, no signal to tune the skills on, and no provenance file was written. In that case do not write `evaluation-<slug>.md`; instead print a one-line note: `evaluation: skipped — only custom-review ran (no A/B comparison)`. Steps 5–7 (merge, apply, verify) still happened, so the fixes are real; only the comparison artifact is omitted.

Otherwise (codex ran), write to `tmp/multi-review/evaluation-<slug>.md`. Always written when codex ran — even when fixes were declined. Fix-grounded fields without evidence are explicitly marked `not assessed (fixes declined)`; do not guess.

**Gate-check is never part of the A/B.** It reviews a different axis (conformance, not correctness), so it appears in neither reviewer scorecard and is never ranked against codex/custom-review. At most note in section 1 that it ran and how many findings it contributed to the merge; the comparison is strictly codex vs. custom-review.

Required sections:

### 1. Run metadata

- Target (display phrase), slug, date.
- Args / focus text forwarded.
- `fixes_applied`: true / false.
- Per-reviewer status (ok / failed-with-reason, findings count).
- Verification step outcome (command run, result, or "skipped: <reason>", or "n/a (fixes declined)").

### 2. Per-reviewer scorecard

One subsection per reviewer (codex, custom-review). For each, report:

- **Findings raised:** count, with severity breakdown.
- **Real findings:** how many turned out to be real after fixing. Cite 1–3 by short title. *(If `fixes_applied=false`: `not assessed (fixes declined)` — but still report the merge-stage decisions from `provenance-<slug>.md`: kept after re-read vs. dropped as hallucination.)*
- **False positives:** count, with one concrete example. *(If `fixes_applied=false`: use merge-stage drops only.)*
- **Under-statement:** findings whose severity or scope was understated. *(`not assessed` if fixes declined.)*
- **Over-statement:** findings whose severity, scope, or certainty was overstated. *(`not assessed` if fixes declined.)*
- **Signal-to-noise:** real / total (or kept-after-merge / total if fixes declined). One sentence on the dominant noise type.
- **Unique depth:** findings only this reviewer raised that survived merge / fix. At least one cited example if any.

### 3. Comparison table

Single markdown table. Rows: total findings, kept-after-merge, real-after-fix (or `—` if declined), false positives, blocking real / claimed, unique-real (or unique-kept), S/N ratio, depth rank (1–2). One column per reviewer.

### 4. Narrative (2–4 paragraphs)

Which review was most useful and why, in concrete terms grounded in either the fix experience or the merge-stage evidence. Which was least useful and why. Patterns visible across runs that hint at skill improvements (e.g., "`custom-review` consistently over-states TUI render-path claims" or "`codex` reliably catches cross-component / sibling-parity bugs `custom-review` misses by validating components in isolation"). Avoid generic praise; cite findings.

### 5. Skill-improvement hypotheses

A short bullet list of concrete edits to `custom-review` or the codex prompt that would have improved this run. Each bullet names the skill, the change, and the finding(s) that motivated it. This is the deliverable that makes the A/B testing actionable.

### 6. Open-Question resolution status

For each Open Question raised by any reviewer in their original `tmp/multi-review/*-<slug>.md`, walk the merged fix commit (and any Finding from another reviewer that landed in the merge) for code that defends the OQ's path — a check, regression test, error return, fallback, or bounds check citing the same condition.

Format as a bullet list, one entry per OQ:

```
- **<reviewer>**: <OQ short title> at <file:line>
  - status: <resolved-by-fix → <commit SHA / Finding ID> | carried (no defending change found) | not-applicable (fixes declined)>
  - one-line pointer if resolved
```

Rules:

1. This section reads the OQs verbatim from each reviewer's review file at `tmp/multi-review/<reviewer>-<slug>.md`. Do not infer OQs from the merged review — only the originals.
2. An OQ is `resolved-by-fix` only if a defending change in the fix commit (or merged Finding) cites the same condition. A change that merely touches the file is not a defence.
3. `carried` is the default when no defending change exists. It means the OQ is still open against the post-fix code.
4. If `fixes_applied=false`, every OQ is `not-applicable (fixes declined)`.
5. Do NOT modify the original reviewer's review file. The annotation lives only in `evaluation-<slug>.md`.

This surfaces credit/attribution for OQs that a peer reviewer's Finding (or codex's fix-driving framing) defended against — critical for the cumulative dataset's understanding of which OQ → fix paths are real signal. See `/home/andrzej/.agentic/tmp/cr2-iteration/multi-review-followup-D3.md` for the original rationale (PR #139 R1 OQ1 → codex F1 chain).

When codex ran and the evaluation was written, print only a short summary to the operator:

- Path to the evaluation file.
- One-line "ranked best → worst" verdict.
- The top 1–2 skill-improvement hypotheses, verbatim from section 5.

Do not re-print the evaluation in full — the operator can read the file. (In the codex-skipped case, the one-line `evaluation: skipped …` note above is the whole summary.)

## Failure modes — quick reference

| Failure | Action |
|---|---|
| Not inside a git repo | Refuse |
| `codex` not on `PATH`, `--codex` passed | Refuse (explicit codex request can't be honored) |
| `codex` not on `PATH`, no `--codex` | Proceed; codex gate forces `run_codex=false` with a note |
| `custom-review` skill missing | Refuse |
| `gh` missing or unauthenticated (PR target only) | Refuse with the specific missing piece |
| Args use rejected shorthand (`branch X`, `staged`) | Refuse with the corrected form |
| Args ambiguous (multiple target hints) | One short multiple-choice question |
| PR head branch ≠ current branch | Abort with `gh pr checkout <num>` instruction |
| PR head OID ≠ local HEAD OID | Abort with the appropriate fetch / push / rebase guidance for ahead / behind / diverged |
| PR target with dirty worktree | Abort; tell operator to commit, stash, or discard first |
| Target has no diff | Refuse |
| Output files already exist for this slug | Interactive: `AskUserQuestion` overwrite y/n, exit on no. `--auto-apply`: overwrite with a one-line notice, no prompt. |
| Both `--codex` and `--no-codex` passed | Refuse — contradictory |
| `--codex` passed | Codex gate forced on; codex runs (refuse earlier if codex absent) |
| `--no-codex` passed | Codex gate forced off; custom-review only; no evaluation |
| No codex flag (auto-decide) | Step 2.5 gate decides from change-nature + round; announce the one-line decision |
| Codex gate-skipped (auto or `--no-codex`) | Single-reviewer merge; gate verdict still emitted (Step 5); **no evaluation / provenance**; print `evaluation: skipped` note |
| Codex ran but fails / empty / times out | Mark sidecar `ok:false` (genuine failure); continue on custom-review; treat as single-reviewer for the eval (skip eval — no comparison) |
| custom-review fails, codex ran OK | Proceed on codex alone (single-reviewer merge); skip eval (no comparison) |
| custom-review fails, codex skipped/failed | No usable review — print reason(s) and exit before merging |
| Operator declines to fix | Skip Steps 6–7; still write evaluation (if codex ran) with fix-grounded fields marked `not assessed` |
| `--auto-apply` passed in args | Skip the Step 2 collision prompt (overwrite) and the Step 5 apply prompt; apply all merged findings automatically. Does **not** affect the codex gate. Evaluation still written *if codex ran* |
| Repo has no `.claude/skills/gate-check/SKILL.md` | Skip Reviewer C **silently** — it is a per-repo opt-in; the repo is wholly unaffected and nothing about gate-check is printed |
| Repo defines gate-check, but it fails | Announce `gate-check: failed — <reason>`; sidecar `ok:false`; continue without it (never aborts the run — custom-review stays load-bearing) |
| Gate-check raises a critical finding | It merges into the blocking section like any reviewer's; counts toward the gate verdict's `N`; excluded from the codex A/B evaluation |
