---
name: multi-review
description: Review a target with two claude reviewers in parallel — `/custom-review` and the built-in `/code-review` — always, plus codex `/review` when the change is significant enough to justify codex's limited budget. By default multi-review auto-decides whether to run codex from the change's significance and the review round; the caller can force it with `--codex` / `--no-codex`. Saves verbatim reviewer outputs to `tmp/multi-review/`, synthesizes a merged best-of review, optionally applies the fixes, and writes an evaluation comparing every correctness reviewer that ran on accuracy, signal-to-noise, and depth (this powers iterative improvement of the review skills). Codex runs as a plain `/review` with only the target; non-target trailing text after `/multi-review` is forwarded verbatim to both claude reviewers as additional focus.
---

# Multi Review

## Purpose

`/multi-review` reviews a target with **two claude reviewers in parallel** — `/custom-review` and the built-in `/code-review` — always, and, **when warranted**, codex `/review` alongside them, then synthesizes a merged best-of review. Every run emits a **gate verdict** — the pre-fix critical count, `pass` iff zero — which is the skill's primary machine-readable output and is computed from the merged review independent of which reviewers ran (see Step 5). Every run with ≥2 usable correctness reviews also writes an evaluation comparing them, so the user can A/B-test the review skills and improve them over time. The gate is the verdict; the evaluation is the analysis.

### Reviewer roster

Reviewers are grouped by **axis** (what they look for) and **gating** (when they run):

| Reviewer | Axis | Runs |
|---|---|---|
| **A — codex `review`** | correctness | gated by change significance + round (Step 2.5) |
| **B — `/custom-review`** | correctness | always |
| **C — `/code-review`** (built-in) | correctness | always |
| **D — `.claude/skills/gate-check`** | repo-convention conformance | only when the repo defines it |

The three correctness reviewers are deliberately different instruments on the same axis: `custom-review` is a single deep read gated on proof-at-file:line, `code-review` is a fan-out of per-angle finders whose candidates face an independent verifier, and codex is an outside model. Their findings merge into one review (Step 4) and all count toward the gate. A–C are also the reviewers the evaluation compares (Step 8); D is excluded because a conformance finding has nothing to be ranked against.

**Why `code-review` is ungated** (unlike codex): it runs on the local subscription with no separate budget to exhaust, so there is nothing to ration. Its cost scales with the effort level instead — see Step 3's level resolution.

**Repo-local conformance reviewer (generic extension point).** This is a documented plug, not a
reference to any one project: **any** repository may opt in by defining a skill at
`.claude/skills/gate-check/SKILL.md` that supports a review mode taking the same target arg and
returning a findings report. When that file exists at the repo root, it runs as a fourth reviewer
on a different axis — repo-convention conformance (e.g. ADR/spec violations, stale living docs,
size budgets) rather than correctness — and is otherwise inert: a repo without it is **wholly
unaffected** and the skill never mentions it. The coupling is exactly the slug + path + the
review-mode/report shape below; no repo specifics live in this skill. It always runs when present
(no budget gate), its findings merge like any reviewer's and so its criticals count toward the
gate verdict, but it is **excluded from the evaluation** (different axis, nothing to
compare).

**Codex is selective by design.** Codex is the higher-signal reviewer — it routinely catches issues the others miss — but its usage budget is far lower and is easily exhausted. So codex runs only when the change is worth that budget: a fundamental/critical change with far-reaching effects, or one with enough technical subtlety to be easy to get wrong. It should *not* burn budget on mechanical, doc, config, or UI changes, or on routine re-review rounds where a slip is low-stakes. That decision is made by the **codex gate** in Step 2.5 — auto-decided by default, or forced by the caller with `--codex` / `--no-codex`. The 99% path is an agent invoking `/multi-review` and letting the gate decide; centralizing the logic here (rather than in every caller) is deliberate, so it can be tuned in one place.

Key difference from `/codex-review`: this skill is **invoked fresh** (not after a prior `/review`). The target must be determined from `/multi-review` arguments, not from earlier conversation context.

## Hard preconditions

Refuse with a clear, short message if any fail:

1. **Working directory is inside a git repository.** Every reviewer resolves its diff from a working tree.
2. **`codex` is on `PATH`** — *only required when codex will actually run.* Run `command -v codex`. If missing: when the caller passed `--codex` (an explicit request for codex), refuse and tell the operator to install codex; otherwise do **not** refuse — record that codex is unavailable and let the codex gate (Step 2.5) force `run_codex = false` with a note. The skill stays useful with `custom-review` alone.
3. **The `custom-review` skill is available.** If it is missing from the available-skills list, refuse.
4. **`claude` is on `PATH`** — Reviewer C (`code-review`) runs as a nested non-interactive `claude -p "/code-review …"` call, for the reason below. Run `command -v claude`. If missing, do **not** refuse: record Reviewer C as unavailable and continue on the remaining reviewers.

   **Why a nested CLI and not the Skill tool.** `code-review` is a Claude Code built-in that is marked user-invocable only; the Skill tool refuses it with `Skill code-review cannot be used with Skill tool due to disable-model-invocation`. A `-p` prompt counts as user input, so `claude -p "/code-review …"` resolves it. **Never instruct a subagent to "invoke the `code-review` skill" instead** — observed failure mode: the subagent hits that error and silently substitutes the nearest listed skill (`custom-review`, or a plugin named `code-review-skill`), which makes multi-review compare `custom-review` against itself and report it as two independent reviewers. That failure is silent in the merged review, which is what makes it worth this precondition.
5. **`gh` is on `PATH` and authenticated** — *only* if the target is `pr`. Run `command -v gh` and `gh auth status`. If either fails, refuse with the missing piece.

## Step 1 — Parse args and determine target

Split `/multi-review`'s trailing text into three buckets:

- **Target hints** — phrases that explicitly identify what to review (see table below).
- **Control flags** — recognized control tokens that change skill behavior, not forwarded as focus text. Recognized:
  - `--auto-apply` — run non-interactively, for programmatic callers (another skill or subagent where no human is present to answer prompts). It skips **every** interactive prompt this skill would otherwise raise: (1) the Step 5 "Apply these fixes now?" prompt — proceed straight to Step 6 (apply fixes); and (2) the Step 2 collision prompt — overwrite any existing output files for the slug instead of asking. The evaluation is still written in Step 8. **`--auto-apply` does not influence the codex gate** — it governs prompts only, not whether codex runs.
  - `--codex` — force codex to run regardless of the Step 2.5 auto-decision. Use when the caller has already judged the change worth codex's budget.
  - `--no-codex` — force codex to be skipped regardless of the auto-decision. `custom-review` still runs.
  - Passing both `--codex` and `--no-codex` is contradictory — refuse with a one-line message.
- **Focus text** — everything that doesn't match a target hint or control flag; forwarded verbatim to **both claude reviewers** (custom-review as additional focus, code-review appended to its target argument, which the skill treats as scope guidance). Codex is not given focus text — it runs as a plain `/review` with only the target flags. Forwarding to both keeps the two always-on reviewers comparable in Step 8: if only one saw the operator's focus, differences in what they surfaced would partly measure the prompt, not the reviewer. (Focus text still informs the codex gate's read of the change — see Step 2.5.)

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
   - **Local ahead** (PR head is an ancestor of HEAD): abort with `git push` guidance — codex would review your local commits while `custom-review` and `code-review` resolve the GitHub PR head, so the reviewers would see different code and their findings would not be comparable.
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
- **code-review target string.** `code-review` takes a free-form target that its scope agent turns into a diff command, so it needs its own phrasing — its parser understands a PR number, a branch, a ref range, or a path, and falls back to the current branch diff for anything it can't narrow. Passing `custom-review`'s canonical arg instead would silently mis-scope (`uncommitted` is not a ref, and `against X` is not a ref range):
  - `pr` → `<baseRefName>...HEAD`
  - `branch` → `<X>...HEAD`
  - `commit` → `commit <sha> — review exactly that commit's diff (git show <sha>)`
  - `uncommitted` → `the uncommitted changes in the working tree (git diff HEAD, plus untracked files)`

  **A PR target is deliberately expressed as a local ref range, not as `<N>`.** Given the PR number, `code-review` would resolve the diff with `gh`, which cannot run inside the nested session's sandbox (per CLAUDE.md) and would fail there rather than in a place the operator can see. The PR preflight above already guarantees the local checkout *is* the PR head — right branch, equal OIDs, clean worktree — so `<baseRefName>...HEAD` is the same diff with no network and no `gh`.

  Never omit this argument. With no target, `code-review` reviews the current branch *plus* any uncommitted changes — a superset of every target above, which would break comparability with the other reviewers.

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
- `tmp/multi-review/code-review-<slug>.md`
- `tmp/multi-review/merged-<slug>.md`
- `tmp/multi-review/evaluation-<slug>.md`

Plus per-reviewer status sidecars (see Step 3):

- `tmp/multi-review/codex-<slug>.status.json`
- `tmp/multi-review/custom-review-<slug>.status.json`
- `tmp/multi-review/code-review-<slug>.status.json`

**Collision check.** Before running anything, check if any of these files already exist.

- **Interactive (no `--auto-apply`):** if any exist, warn the operator listing which files exist, and ask via `AskUserQuestion` whether to overwrite. Exit on "no".
- **`--auto-apply` passed:** do **not** prompt — there is no human to answer, and a prompt here would stall an autonomous multi-round loop. The slug is stable across rounds (`pr<N>`, or `branch-<name>-<hash>` hashed from the branch *name*, not the diff), so round 2+ always collides with round 1's files. Overwrite the existing outputs, printing a one-line notice naming the slug being overwritten.

Then `mkdir -p tmp/multi-review/`.

## Step 2.5 — Codex gate: decide whether codex runs

`custom-review` and `code-review` always run. This step decides a single boolean, `run_codex`, that governs whether codex `/review` runs alongside them. Resolve it in **precedence order** — the first matching rule wins:

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

Every enabled reviewer starts in a **single message**, one tool call each, so they all run concurrently:

- **Always:** Reviewer B (foreground `custom-review` Agent) and Reviewer C (background `code-review` CLI call). These two are the parallel claude reviewers; neither is conditional — the only thing that skips C is `claude` missing from `PATH` (precondition 4).
- **Only if `run_codex` is true:** Reviewer A (background codex Bash call). When false, **skip Reviewer A entirely** — no codex Bash call, no `codex-<slug>.*` files, no background process to monitor.
- **Only if `.claude/skills/gate-check/SKILL.md` exists at the repo root:** Reviewer D. Check with a single `test -f` *before* composing the message; if it is absent there is no Reviewer D and nothing about gate-check is printed.

### Effort level for `code-review` (resolve before composing the message)

`code-review`'s **first argument token is its effort level**, and the level sets the review's *shape*, not merely how hard it thinks:

| Level | Shape | Cap |
|---|---|---|
| `low` / `medium` | single inline pass, no verify | ≤4 findings |
| `high` | 3 correctness finders + 1 cleanup finder, one verifier per (file, line) | ≤10 findings |
| `xhigh` / `max` | 5 correctness finders + 1 cleanup finder, plus a gap sweep | ≤15 findings |

At `low` and `medium` it also skips test and fixture hunks outright, so at those levels it reviews no test changes at all — which is why Step 8 reads its misses against its level rather than as judgment.

Omitting the token pins `high` **regardless of the session's effort** — the level is not inherited. Only the reasoning effort of the agents the review spawns is. So pass the level explicitly, or an `xhigh` session silently gets a `high`-shaped review. Resolve it with one Bash call in *this* context before spawning:

```sh
printf '%s\n' "$CLAUDE_EFFORT";
```

- Value in `low|medium|high|xhigh|max` → that is `<cr-level>`; use it both as the level token and as `--effort <cr-level>` on the nested CLI call below.
- Empty or unrecognized → omit both, and record `"level":"high (default — CLAUDE_EFFORT unset)"` in the status sidecar, so a review that ran shallower than the session did is visible afterwards.

`$CLAUDE_EFFORT` is the orchestrating turn's effort *after* any model-driven downgrade — i.e. the level the review can actually run at — which is why it is read here rather than assumed. It must be passed explicitly because Reviewer C runs as a **fresh non-interactive `claude` session** (below), and a fresh session starts at the configured default effort; nothing about the orchestrator's level is inherited across that boundary. The two arguments do different jobs and are both needed: the level *token* picks the fan-out shape, `--effort` sets how hard each spawned agent thinks.

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

### Reviewer C — claude `/code-review` (background Bash, nested CLI)

`code-review` cannot be invoked through the Skill tool (precondition 4), so it runs as a nested non-interactive session whose stdout *is* the review. That makes it structurally the same kind of reviewer as codex: one background Bash call, stdout redirected to the canonical path, a status sidecar written by the shell. Nothing needs collecting in Step 3.5 beyond the guard.

Run it with a single background Bash call (`run_in_background: true`, timeout 600000 ms) in the same message as the other reviewers:

```sh
claude -p "/code-review <cr-level> <code-review target string>" \
  --effort <cr-level> \
  --allowedTools "Bash(git *)" Read Grep Glob Task Workflow \
  --disallowedTools ReportFindings \
  > tmp/multi-review/code-review-<slug>.md 2> tmp/multi-review/code-review-<slug>.stderr;
rc=$?;
printf '{"reviewer":"code-review","exit":%d,"level":"<cr-level>","output":"tmp/multi-review/code-review-<slug>.md"}\n' "$rc" > tmp/multi-review/code-review-<slug>.status.json;
```

Substitutions and why each argument is there:

- **`<cr-level>`** — from the level resolution above. When `CLAUDE_EFFORT` was unset, drop *both* the token and `--effort` (leaving `/code-review <target>`), rather than guessing a level.
- **`<code-review target string>`** — the code-review phrasing from Step 1, with the operator's focus text appended after an em dash when there is any. The skill treats the whole argument as scope guidance.
- **`--allowedTools`** — the review must be read-only. This allowlist is what keeps it that way: no `Write`, no `Edit`, no unrestricted `Bash`. `Task` and `Workflow` are required — at `high` and above the review *is* an agent fan-out, and without `Workflow` it silently degrades to a single inline pass. The cost of the narrow `Bash(git *)` is that the review cannot *execute* the code it is reviewing to confirm a hypothesis; in `-p` mode a denied call returns an error to that session instead of prompting, so it degrades to reading rather than stalling. That trade is deliberate: an autonomous reviewer that can run arbitrary commands in the repo is a worse problem than one that occasionally reasons instead of measuring.
- **`--disallowedTools ReportFindings`** — `code-review`'s normal output contract is one `ReportFindings` tool call, whose payload never reaches stdout. Denying the tool makes the skill take its text/JSON output branch, so the findings land in the review file. Without this the file can come back as a bare summary line with the findings lost inside a tool call.
- **Trailing `;`** per CLAUDE.md guards the sandbox pipe-drop bug. Keep stderr separate so the output file stays parseable as a review.

**Empty-output guard** (same shape as codex's). If `exit != 0` or `stat -c %s tmp/multi-review/code-review-<slug>.md` reports `0`, mark the sidecar `"ok": false` with the exit code and a pointer to the `.stderr` file. Two specific failures to name in the reason, because both produce a zero-byte file:

- **`--effort <cr-level>` rejected** (the level is restricted for the session's model). Retry **once** without `--effort`, keeping the level token, and note the downgrade in the sidecar — the shape still tracks the session even when the reasoning effort cannot.
- **Nested-session auth or rate-limit failure.** Do not retry; record and continue on the other reviewers.

### Reviewer D — repo-local gate-check (Agent tool, foreground) — *only if the repo defines it*

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

### Why background Bash + foreground Agents in one message

Every reviewer is independent, so issuing all their tool calls in one message is what makes them actually run in parallel rather than in sequence. The split by mechanism is deliberate:

- **Background Bash** for codex and `code-review` — both are external processes that can outrun a single tool timeout, and both write their own output file plus a status sidecar, so the parent has a completion signal it can poll.
- **Foreground Agents** for `custom-review` and gate-check — an Agent's result returns when it completes, and both need their reply parsed for the path they wrote.

After this message, wait for the foreground Agent(s) and monitor the background process(es) to completion before proceeding to Step 3.5. In the common case (codex gate-skipped) that is one background `code-review` process plus one foreground `custom-review` Agent.

**Announce Reviewer C's status in one line** once it returns, mirroring the codex and gate-check one-liners, so a shallower-than-expected or failed run is never silent:

```
code-review: <ran at <level>, N findings | failed — <reason>>
```

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

**Reviewer C (`code-review`):** it wrote the canonical file itself, so there is nothing to copy — only to validate:

1. Confirm `tmp/multi-review/code-review-<slug>.md` exists and is non-empty, and that the sidecar's `exit` is `0`. Apply the empty-output guard from Step 3 (including the one `--effort` retry).
2. On success, extend the sidecar to the full shape, counting findings from the file:
   ```json
   {"reviewer":"code-review","ok":true,"level":"<cr-level>","mode":"<fan-out|single-pass|unstated>","findings":<N>,"output":"tmp/multi-review/code-review-<slug>.md"}
   ```
   Derive `mode` from the review's own text: `single-pass` when it says it ran inline without the multi-agent fan-out (the skill is instructed to state this when the `Workflow` tool was unavailable), otherwise `unstated` unless it actually described the fan-out. Record `unstated` rather than assuming `fan-out` — Step 8 reads this to decide whether a thin round was a shape limit or a judgment call, and a guess there would corrupt the cumulative dataset.
3. On failure: `"ok":false,"reason":"<exit code + stderr pointer>"`. Leave the output file as-is — the nested CLI's own error text is useful evidence. A failed `code-review` never aborts the run.
4. **Sanity-check that it is not a second `custom-review`.** If the file's body reads as a `custom-review` report (Open Questions section, `binding-source:`/notes-ledger structure, a `tmp/custom-review-<ts>/` self-reference), the nested session resolved the wrong reviewer. Mark the sidecar `"ok":false,"reason":"resolved wrong skill — output looks like custom-review"` and **exclude it from the merge**; a duplicate of Reviewer B would manufacture false consensus in Step 4 and a meaningless comparison in Step 8. This is the observed failure mode from precondition 4, so it is checked rather than assumed away.

**Reviewer D (gate-check), when it ran:** same collection pattern as Reviewer B — parse
`REPORT_PATH=`, copy the report to `tmp/multi-review/gate-check-<slug>.md`, and write
`tmp/multi-review/gate-check-<slug>.status.json` with `findings` and `criticals` counts. On
failure, write the `FAILED: <reason>` placeholder and an `"ok":false` sidecar; a failed
gate-check never aborts the run (custom-review remains the load-bearing reviewer).

**Post-write sanity check.** Before proceeding to Step 4, confirm that every reviewer that ran has its own distinct output file: `custom-review-<slug>.md`, `code-review-<slug>.md`, and (if codex ran) `codex-<slug>.md`.

For codex (Reviewer A):

- **Gate-skipped (`run_codex = false`):** no codex output or sidecar was produced. Write a sidecar that records the *skip* (distinct from a failure) so later steps can tell them apart:
  ```json
  {"reviewer":"codex","ok":false,"skipped":true,"reason":"codex gate: <reason from Step 2.5>"}
  ```
- **Ran (`run_codex = true`):** the status sidecar was already written by the bash command. If `exit != 0` or the output file is empty (`stat -c %s ... -eq 0`), update its status to `"ok":false` (a genuine failure, not a skip) and leave the output file as-is (codex's own error messages are useful evidence).

**Abort condition.** Abort only when **no correctness reviewer produced a usable review** — i.e. custom-review failed *and* code-review failed or was unavailable *and* codex either failed or was gate-skipped. In that case print the reason(s) and stop before merging. A gate-skipped codex is **not** a failure, and neither is one claude reviewer failing while the other succeeded: proceed on whatever usable reviews exist. (Gate-check alone is not enough to proceed — it reviews conformance, not correctness, so a run with only its output would gate the fixes on the wrong axis.)

## Step 4 — Synthesize merged review

`Read` each available `tmp/multi-review/*-<slug>.md` output (skip any whose status sidecar is `"ok":false` — this includes a gate-skipped codex). Produce **one** merged review and write it to `tmp/multi-review/merged-<slug>.md`.

**The normal case is two correctness reviews** (custom-review + code-review), three when codex ran. **Single-reviewer case** — one claude reviewer failed and codex did not run: the merge degrades to a pass-through, still applying synthesis rule 2 (re-read each finding's cited code and keep only those you now believe are real), still grouping by severity, still single-voice. The consensus rule (1) is moot with one reviewer. A merged review is still produced because Step 6 applies fixes from it. (Gate-check, when it ran, is an extra source in either case — "single-reviewer" counts the correctness axis only; conformance findings still merge in.)

**`code-review` findings in the merge — two rules, because its output shape differs:**

1. **Severity is usually absent.** Its reporting contract is `file`, `line`, `summary`, `failure_scenario`, a `category` slug, and (when a verify pass ran) a `verdict` — ranked most-severe-first but with no `blocking`/`medium`/`optional` label. In practice it sometimes volunteers severity words anyway. So: where it labelled a finding, treat that label as the reviewer's own and re-check it like any other reviewer's; where it did not, **you assign the severity during the merge**, from the `failure_scenario`'s actual impact, using the same bar you apply elsewhere. Never infer severity from rank position, and never treat "unlabelled" as non-blocking — the gate counts the merged review's blocking section, so this is where a real bug would quietly stop failing the gate.
2. **`PLAUSIBLE` is not `CONFIRMED`.** `code-review` keeps both: `CONFIRMED` means it named the triggering inputs and quoted the line; `PLAUSIBLE` means the mechanism is real but the trigger is uncertain. A `PLAUSIBLE` finding may only be merged as **blocking** if your own re-read (rule 2) establishes the trigger; otherwise merge it at the severity its confirmed part supports, or move it to Open Questions. `CONFIRMED` findings still go through rule 2 like everything else.

Its `category` slug also tells you what kind of finding it is (`correctness`, `simplification`, `efficiency`, `reuse`, `altitude`, `conventions`, `test-coverage`, …). Cleanup-category findings are `optional` unless they name a concrete maintenance cost — correctness outranks cleanup whenever the merged review has to cut.

**Gate-check findings in the merge:** they enter the merged review like any reviewer's, with one
extra rule — preserve each finding's `binding-source:` citation (ADR / living doc / budget pin)
in the merged entry; that citation is what makes a conformance finding actionable. Synthesis
rule 2 (re-read before keeping) applies to them too.

Synthesis rules (same as `codex-review` Step 5):

1. **Findings flagged by 2+ reviewers** — keep, dedupe to one entry. Use the clearest wording. Note multi-reviewer agreement as `(consensus: <reviewers>)` next to the heading — naming *which* reviewers agreed, since with three correctness reviewers "2 of 3" and "3 of 3" are different evidence, and the evaluation step reads this.
2. **Findings flagged by only one reviewer** — re-read the actual code with `Read`. Keep only if you now believe it's real. Drop hallucinations and noise.
3. **Disagreements** — pick the position you now believe correct after re-reading. Do not mark as "disputed".
4. **Voice** — single unified reviewer voice. No "codex said X / custom-review said Y" attribution in the body (the `(consensus: …)` tag is the one exception, and provenance lives in its own file).
5. **Structure** — group by severity (blocking → medium → optional). File:line references on every finding.

**Whenever ≥2 correctness reviewers produced usable reviews** (the normal case, since custom-review and code-review both always run), also write `tmp/multi-review/provenance-<slug>.md` capturing, per finding (kept or dropped):

- Which reviewer(s) raised it, and each one's own severity label or verdict as it arrived.
- Kept / dropped / merged decision and one-line reason.
- For findings you re-severitied (all of `code-review`'s, plus any relabelled), the severity you assigned and why.

The evaluation step (Step 8) uses this directly; never lose it to in-memory state. Skip the provenance file only in the degenerate single-correctness-reviewer case, where there is nothing to compare and Step 8 is skipped too.

## Step 5 — Emit the gate verdict, print merged review, ask to fix

Print the full contents of `merged-<slug>.md` inline in the chat.

### Gate verdict (always emitted — reviewer-roster-independent)

The **gate** is the pre-fix critical count, and it is the skill's primary machine-readable output: callers such as `plan-implement-merge` loop on it (review → fix → re-review) until it reads zero. The merged review always groups findings by severity (blocking → medium → optional) and is produced *before* any fixes (Step 6), so its blocking section **is** the pre-fix critical set — whichever reviewers contributed to it. Count it from the merged review and print exactly one line:

```
gate: <pass|fail> — <N> pre-fix critical finding(s) [reviewers: custom-review+code-review[+codex][+gate-check]]
```

`pass` iff `N == 0`. Treat any finding the merged review labels `blocking`, `critical`, or `P0` as critical (the merge groups under a `blocking` heading; the synonyms guard against drift). Because gate-check findings merge in like any reviewer's (Step 4), a critical **conformance** finding counts toward `N` and can fail the gate on its own — that is the point of running it in the cycle. `code-review` findings count too, at the severity the merge assigned them (Step 4) — a reviewer that ships no severity labels still moves the gate. List in the `reviewers:` tag only the reviewers that actually produced a usable review. This line is emitted on **every** run, so the no-criticals gate never depends on any one reviewer having run.

Examples: `gate: pass — 0 pre-fix critical finding(s) [reviewers: custom-review+code-review]`; `gate: fail — 2 pre-fix critical finding(s) [reviewers: custom-review+code-review+codex]`; `gate: fail — 1 pre-fix critical finding(s) [reviewers: custom-review+gate-check]` (code-review failed this round).

### Apply prompt

**If `--auto-apply` was passed in the args**, skip the prompt entirely: set `fixes_applied=true`, print a one-line notice ("auto-apply: applying all merged findings without prompting"), and proceed to Step 6. The Step 8 evaluation is still written.

Otherwise, call `AskUserQuestion` with a yes/no:

- **Question:** "Apply these fixes now?"
- **Options:** "Yes — apply all merged findings" / "No — skip fixes (evaluation still written)"

Regardless of the answer, an evaluation is written in Step 8 whenever ≥2 correctness reviewers produced usable reviews. The fix experience supplies grounded judgments; without it, evaluation fields that depend on fix evidence are explicitly marked `not assessed (fixes declined)` rather than guessed.

If "no": skip Steps 6 and 7, jump to Step 8 with the `fixes_applied=false` flag.

## Step 6 — Apply fixes (one pass, no per-finding checkpoint)

(Runs if either the operator answered "yes" in Step 5, or `--auto-apply` was passed.)

Apply every blocking and medium finding from the merged review in one pass. Optional/polish findings: apply if cheap, skip if invasive.

While fixing, keep brief notes for the evaluation step:

- Which findings were real, partial, or false alarms once you got into the code.
- Which findings required reading code the reviewer didn't cite (under-statement).
- Which findings exaggerated severity or impact (over-statement).
- Which findings were uniquely deep (would have been missed by the other reviewers) — and which reviewer raised them.

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

## Step 8 — Write evaluation (whenever ≥2 correctness reviewers ran)

Write `tmp/multi-review/evaluation-<slug>.md` comparing **every correctness reviewer that produced a usable review** — normally `custom-review` + `code-review`, three-way when codex also ran. It is written even when fixes were declined; fix-grounded fields without evidence are explicitly marked `not assessed (fixes declined)`, never guessed.

This step used to be codex-only, because codex was the only second opinion available. With `code-review` always running there is a comparison on **every** round, so the evaluation is now the default rather than the exception — which is the point: the cumulative dataset that drives `custom-review`'s improvement no longer depends on codex's budget.

**Skip only in the degenerate case:** fewer than 2 correctness reviewers produced usable output (one claude reviewer failed *and* codex did not run). Then there is nothing to compare and no provenance file was written — print one line, `evaluation: skipped — only <reviewer> produced a usable review (nothing to compare)`, and stop. Steps 5–7 still happened, so the fixes are real; only the comparison artifact is omitted.

**Gate-check is never part of the comparison.** It reviews a different axis (conformance, not correctness), so it appears in no reviewer scorecard and is never ranked. At most note in section 1 that it ran and how many findings it contributed to the merge.

**Reviewers are not compared on equal terms in one respect — say so rather than scoring around it.** `code-review` caps its own output (≤4 findings at `low`/`medium`, ≤10 at `high`, ≤15 at `xhigh`/`max`) and skips test-file hunks at the lower levels; `codex` sees no focus text. When a reviewer's miss is explained by its cap, its level, or its missing focus text, record it as a **structural** miss, not a quality miss — otherwise every round manufactures the same false conclusion about depth.

Required sections:

### 1. Run metadata

- Target (display phrase), slug, date.
- Args / focus text forwarded, and to which reviewers.
- `fixes_applied`: true / false.
- Per-reviewer status (ok / failed-with-reason / skipped-with-reason, findings count).
- `code-review`'s effort level and its `mode` (`fan-out` / `single-pass` / `unstated`) from the sidecar — both bound what it could possibly find, so every later comparison is read against them.
- Verification step outcome (command run, result, or "skipped: <reason>", or "n/a (fixes declined)").

### 2. Per-reviewer scorecard

One subsection per correctness reviewer that ran (`custom-review`, `code-review`, and codex when it ran). For each, report:

- **Findings raised:** count, with severity breakdown — for `code-review`, the severities *you* assigned in the merge, noting that they are merge-assigned rather than reviewer-assigned, plus its own `CONFIRMED`/`PLAUSIBLE` split.
- **Real findings:** how many turned out to be real after fixing. Cite 1–3 by short title. *(If `fixes_applied=false`: `not assessed (fixes declined)` — but still report the merge-stage decisions from `provenance-<slug>.md`: kept after re-read vs. dropped as hallucination.)*
- **False positives:** count, with one concrete example. *(If `fixes_applied=false`: use merge-stage drops only.)*
- **Under-statement:** findings whose severity or scope was understated. *(`not assessed` if fixes declined.)*
- **Over-statement:** findings whose severity, scope, or certainty was overstated. *(`not assessed` if fixes declined.)*
- **Signal-to-noise:** real / total (or kept-after-merge / total if fixes declined). One sentence on the dominant noise type.
- **Unique depth:** findings only this reviewer raised that survived merge / fix. At least one cited example if any.
- **Structural misses:** real findings this reviewer could not have surfaced given its cap, level, or missing focus text — separated from misses that reflect its judgment. Omit the row when there are none.

### 3. Comparison table

Single markdown table, one column per correctness reviewer that ran. Rows: total findings, kept-after-merge, real-after-fix (or `—` if declined), false positives, blocking real / claimed, unique-real (or unique-kept), S/N ratio, depth rank (1–N over the reviewers present). Add a `consensus` row: how many of this reviewer's findings another reviewer independently raised — with three instruments on one axis, agreement is the cheapest available signal that a finding is real.

### 4. Narrative (2–4 paragraphs)

Which review was most useful and why, in concrete terms grounded in either the fix experience or the merge-stage evidence. Which was least useful and why. Where the reviewers' *shapes* explain the difference rather than their quality (`code-review`'s per-angle finders and independent verifier vs. `custom-review`'s single deep proof-gated read vs. codex's outside-model view) — that framing is what makes the pattern transferable instead of a one-off score. Patterns visible across runs that hint at skill improvements (e.g., "`custom-review` consistently over-states TUI render-path claims", "`code-review` reliably catches removed-guard regressions that `custom-review` reads past", "`codex` catches cross-component / sibling-parity bugs `custom-review` misses by validating components in isolation"). Avoid generic praise; cite findings.

### 5. Skill-improvement hypotheses

A short bullet list of concrete edits to `custom-review` that would have improved this run. Each bullet names the change and the finding(s) that motivated it. This is the deliverable that makes the comparison actionable.

`custom-review` is the only reviewer here that is *ours* to edit, so it is the target of every hypothesis. `code-review` is a Claude Code built-in and codex is an external CLI — when one of them beat `custom-review`, the hypothesis is what to port into `custom-review` (an angle it doesn't run, a verification step it skips), not a change to them. Where a *structural* limit explains the gap, the hypothesis may instead be about multi-review's own plumbing (e.g. the effort level it passes).

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
6. `code-review` emits no Open Questions — its output is findings only, and its uncertain candidates arrive as `PLAUSIBLE` findings instead. So it contributes no OQ entries, but it *can* resolve another reviewer's OQ: a `code-review` finding that lands in the merge and names the same condition counts as a defending change like any other.

This surfaces credit/attribution for OQs that a peer reviewer's Finding (or codex's fix-driving framing) defended against — critical for the cumulative dataset's understanding of which OQ → fix paths are real signal. See `/home/andrzej/.agentic/tmp/cr2-iteration/multi-review-followup-D3.md` for the original rationale (PR #139 R1 OQ1 → codex F1 chain).

When the evaluation was written, print only a short summary to the operator:

- Path to the evaluation file.
- One-line "ranked best → worst" verdict over the reviewers compared.
- The top 1–2 skill-improvement hypotheses, verbatim from section 5.

Do not re-print the evaluation in full — the operator can read the file. (In the degenerate case, the one-line `evaluation: skipped …` note above is the whole summary.)

## Failure modes — quick reference

| Failure | Action |
|---|---|
| Not inside a git repo | Refuse |
| `codex` not on `PATH`, `--codex` passed | Refuse (explicit codex request can't be honored) |
| `codex` not on `PATH`, no `--codex` | Proceed; codex gate forces `run_codex=false` with a note |
| `custom-review` skill missing | Refuse |
| `claude` not on `PATH` | Do **not** refuse; record Reviewer C unavailable and continue on the rest |
| `code-review` absent from the model-visible skill list | Irrelevant — it is user-invocable only and never invoked via the Skill tool. Do not skip it and do not refuse |
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
| `--no-codex` passed | Codex gate forced off; the two claude reviewers still run; evaluation still written (they are the comparison) |
| No codex flag (auto-decide) | Step 2.5 gate decides from change-nature + round; announce the one-line decision |
| Codex gate-skipped (auto or `--no-codex`) | Two-reviewer merge; gate verdict emitted as always; evaluation + provenance still written over custom-review vs code-review |
| Codex ran but fails / empty / times out | Mark sidecar `ok:false` (genuine failure); continue on the claude reviewers; evaluation compares the two that remain |
| `CLAUDE_EFFORT` unset or unrecognized | Omit both the level token and `--effort`; `code-review` runs at `high`; record the default in its sidecar |
| `--effort <level>` rejected by the nested CLI (zero-byte output) | Retry once without `--effort`, keeping the level token; note the downgrade in the sidecar |
| `code-review` fails / empty / nested-session auth or rate-limit error | Announce `code-review: failed — <reason>`; sidecar `ok:false`; continue on the remaining reviewers |
| `code-review` output looks like a `custom-review` report | Wrong skill resolved — mark `ok:false`, **exclude from the merge** (a duplicate would fake consensus and void the comparison) |
| `code-review` ran single-pass (no `Workflow`) | Usable — merge it, but record the mode in the sidecar and section 1, and read its misses as structural |
| custom-review fails, code-review or codex OK | Proceed on whichever ran; evaluation only if ≥2 correctness reviews are usable |
| No correctness reviewer produced a usable review | Print reason(s) and exit before merging (gate-check alone is the wrong axis to gate on) |
| Operator declines to fix | Skip Steps 6–7; still write the evaluation with fix-grounded fields marked `not assessed` |
| `--auto-apply` passed in args | Skip the Step 2 collision prompt (overwrite) and the Step 5 apply prompt; apply all merged findings automatically. Does **not** affect the codex gate. Evaluation still written |
| Repo has no `.claude/skills/gate-check/SKILL.md` | Skip Reviewer D **silently** — it is a per-repo opt-in; the repo is wholly unaffected and nothing about gate-check is printed |
| Repo defines gate-check, but it fails | Announce `gate-check: failed — <reason>`; sidecar `ok:false`; continue without it (never aborts the run — custom-review stays load-bearing) |
| Gate-check raises a critical finding | It merges into the blocking section like any reviewer's; counts toward the gate verdict's `N`; excluded from the evaluation |
