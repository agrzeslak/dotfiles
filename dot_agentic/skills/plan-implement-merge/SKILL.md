---
name: plan-implement-merge
description: End-to-end pipeline that plans a change with superpowers, hardens the plan via a codex + plan-review-skill review loop, implements it test-driven via subagents, then hardens the implementation through a local multi-review loop until no critical findings remain, opens a review-clean PR, gates the merge on a green CI run, then runs cleanup. Use when the user invokes `/plan-implement-merge <description or path>` and wants the whole plan → review → implement → review → PR → merge pipeline run autonomously. Argument is auto-detected as a file path (if it resolves on disk) or treated as an inline description otherwise.
---

# Plan → Implement → Merge

Autonomous pipeline. Given a description or spec path, this skill plans, reviews the plan, implements TDD via subagents, iterates a local multi-review loop until clean, opens a review-clean PR, gates the merge on a green CI run, and cleans up. No iteration cap — the loops run until their stop conditions are met.

**Two gates, now sequential.** The PR is *opened* only after the multi-review loop reports no pre-fix criticals (step 4) — that loop runs entirely on the local branch (`against <base>`), so no PR exists and no CI fires while review iterates. The PR then *merges* only once CI is green on its head (step 6). The two remain independent checks — a clean AI review is not a passing build — but they no longer overlap on a live PR: review fully precedes the PR, so CI runs on already-reviewed code. The lone crossover is a *substantive* CI fix (step 6), which re-enters the review gate locally before being pushed, so the gates never fall out of sync.

## Argument handling

The trailing text after `/plan-implement-merge` is the **target**. Auto-detect:

- If the trimmed argument resolves to an existing file or directory path, treat it as a **spec reference** — pass the path to the planning step verbatim and instruct the planner to read it.
- Otherwise treat the argument as an **inline description** of the work to do.

If the argument is empty, refuse with a short message asking for a description or path.

## Hard preconditions

Refuse with a clear short message if any fail:

1. **Inside a git repository.**
2. **`gh` is on `PATH` and authenticated.** Run `command -v gh`; capture `gh auth status` output to a file (gh is unsandboxable — never chain it with other commands; always invoke with `dangerouslyDisableSandbox: true`).
3. **Required skills available:** `superpowers:brainstorming`, `superpowers:writing-plans`, `superpowers:test-driven-development`, `superpowers:subagent-driven-development`, `superpowers:verification-before-completion`, `plan-review-skill`, `multi-review`, `cleanup`. Check the available-skills list; refuse with the missing names if any are absent. Additionally, **if** the argument requests isolation (see "Branching" below), also require `superpowers:using-git-worktrees` and refuse if absent — checking now avoids failing mid-run after planning has already started.
4. **`codex` is on `PATH`.** Run `command -v codex`. If missing, refuse — codex is required for the plan-review loop and the multi-review loop.
5. **`multi-review` supports `--auto-apply`.** This pipeline runs `/multi-review` inside a subagent loop where no human is present to answer its "Apply these fixes now?" prompt. Confirm the installed `multi-review/SKILL.md` documents an `--auto-apply` control flag (grep for `--auto-apply`); refuse if absent so the operator can update the skill before relying on an autonomous loop that would otherwise stall.

## Branching

This skill normally runs serially, so worktrees are unnecessary. **Only** create a worktree if the argument explicitly says the work needs isolation (e.g., "in parallel", "isolated worktree", "while other work continues"). In that case invoke `superpowers:using-git-worktrees`.

Otherwise:

- If the current branch is the repo's default branch, create a new feature branch *before* planning. Derive the branch name from a short slug of the argument (e.g., `feat/<slug>`). Switch to it.
- If already on a non-default branch, continue on it.

Record two values that later steps need: the **feature branch name** (just created, or the current non-default branch) and the **base branch** — the repo's default branch that the Step 4 review loop diffs against (`against <base>`) and that Step 5's PR targets. Derive the base once from the repo's default branch (e.g. `git symbolic-ref --short refs/remotes/origin/HEAD`, then strip the `origin/` prefix; fall back to `main`).

## Step 1 — Plan

**Before doing anything else in this step: ask me questions until what we want to implement and how is unambiguously clear.** Drive the conversation interactively — surface ambiguities in scope, acceptance criteria, constraints, data shapes, edge cases, and the intended approach, and keep asking until you can restate the goal and the approach back without hedging. Only proceed to brainstorming/planning once that bar is met. (If the user has explicitly told you to skip clarifying questions for this run, honor that and make the most reasonable call instead.)

Invoke `superpowers:brainstorming` first if the argument is an inline description that lacks concrete scope. Skip brainstorming when the argument points to a spec file that already encodes intent, or when the description is unambiguous.

Then invoke `superpowers:writing-plans` to produce the implementation plan. Forward the argument (description or path) as the source material. Let writing-plans choose the plan file path; capture and remember that path — every later step references it.

## Step 2 — Plan review loop

**Stop rule (read this first):** A round runs a review and then applies fixes. Exit the loop as soon as a round's **pre-fix** findings contain no criticals. Do **not** dispatch a follow-up round to verify the fixes from the previous round — the fixes are trusted, and any residual issues are caught later by the Step 4 review loop. The pre-fix critical count is the *only* gate; non-critical findings in a clean round are applied and then the loop ends without another review.

Dispatch a single subagent per round (fresh context per round) with the round's job spelled out:

```
Round N — plan review

Plan file: <path>

Run these two reviews in parallel:
  1. codex `/review` against the plan file. Save output to tmp/plan-implement-merge/round-N/codex.md.
  2. `/plan-review-skill` against the plan file. Save output to tmp/plan-implement-merge/round-N/plan-review.md.

If codex fails or reports usage exhaustion, continue with plan-review-skill alone, but raise
the stop threshold for this and all subsequent rounds: stop only when no critical AND no high
findings remain (instead of just no-criticals).

Merge findings. Apply every finding regardless of severity by editing the plan file in place.

Report back:
  - Whether codex ran successfully.
  - Counts of findings by severity, per reviewer — counted from the *pre-fix* review output,
    before any edits were applied. Print the explicit critical count (and high count if codex
    was unavailable).
  - Do NOT run a second review to confirm your fixes — the orchestrator decides whether to
    dispatch another round based on the pre-fix counts you report.
```

Severity is reviewer-assigned: trust the labels the reviewers print. Treat anything labeled `critical`, `blocking`, `P0`, or equivalent as critical. If a reviewer labels things inconsistently, take the highest severity it assigned for that finding.

Loop:

1. Dispatch the subagent for round N.
2. Read its report and look at the pre-fix critical count (and pre-fix high count if codex was unavailable this round).
3. If that count is 0, the loop is **done** — the round's fixes are already applied, exit immediately. Do not dispatch a verification round.
4. Otherwise increment N and repeat.

Anti-rule: never dispatch round N+1 solely to confirm the fixes from round N landed cleanly. The next round only exists to surface new criticals; if round N's pre-fix already had none, there is nothing to confirm here.

## Step 3 — Implement (TDD, subagent-driven)

The plan from step 2 is now hardened. Implement it using `superpowers:subagent-driven-development` as the execution model and `superpowers:test-driven-development` as the methodology — each task in the plan is dispatched to a subagent that writes tests first, then implementation, then verifies.

Follow the subagent-driven-development skill exactly for fan-out/serialization rules. Each subagent receives the plan path, the specific task it owns, instructions to use TDD, and the comment-hygiene directive below.

**Comment hygiene — include this verbatim in every code-writing subagent prompt (this step, the Step 4 review loop, and the Step 6 CI-fix subagent):**

> The plan's task, PR, wave, and commit identifiers (e.g. `Task 4`, `PR 6`, `H2-PR-2`, `Lane J Task 17`) and the plan file name are orchestration scaffolding for this run — not documentation of the code. **Never carry them into code or doc comments.** Every comment must describe present behavior, intent, or rationale for a reader who never saw the plan. If a reference is genuinely load-bearing for an explanation, cite a durable, externally-resolvable handle — a concrete GitHub `#NNN` or `ADR NNNN` — never an internal task/PR/plan label. (This mirrors the "Comments describe the code, not the process that produced it" rule in the repo's `AGENTS.md`; defer to that file if it conflicts.)

This is the root-cause fix for process-reference leakage: the labels are salient in a subagent's context precisely because we hand it a numbered task, so the prohibition has to travel with the task.

After all tasks complete, run `superpowers:verification-before-completion` against the plan's acceptance criteria before moving on. If any verification fails, dispatch a fix-up subagent and re-verify.

## Step 4 — Multi-review loop (local, no PR)

**No PR exists yet.** This loop hardens the branch entirely on its local committed diff (`against <base>`), so it triggers no push, no `gh`, and no CI. The PR is opened in Step 5 only once this loop is clean, so CI runs on already-reviewed code instead of on every intermediate fix — the whole point of doing review before the PR.

**Precondition — clean tree.** The `against <base>` target diffs *committed* changes only (`git diff <base>...HEAD`). Before the first round, ensure all of Step 3's implementation is committed and the working tree is clean; otherwise the first round's diff is incomplete. Each round's subagent commits its own fixes (below), so the tree stays clean between rounds and every round sees the full, accurate branch-vs-base change.

**Stop rule (read this first):** A round runs `/multi-review` (which itself runs both reviewers and applies fixes) and the subagent commits. Exit the loop as soon as a round's **pre-fix** critical count across both reviewers is 0. Do **not** dispatch a follow-up round to verify the fixes from the previous round — the fixes are trusted. The pre-fix critical count is the *only* gate; non-critical findings in a clean round are applied, committed, and then the loop ends without another review.

Initialize `<repo root>/tmp/review-comparison.md` if it does not exist. The file is a running cumulative log designed to drive **improvements to the claude reviewer (`custom-review`)** specifically — each entry should be actionable for future skill edits (what custom-review missed that codex caught, what it over-flagged, where its depth fell short of or exceeded codex).

Per round:

1. **Dispatch a fresh subagent** with the goal:

   ```
   Round N — multi-review of branch <feature-branch> against <base>

   Run `/multi-review against <base> --auto-apply`. The `against <base>` form selects the
   branch target — multi-review reviews the local committed diff `git diff <base>...HEAD`
   with no PR, no push, and no `gh`. The `--auto-apply` flag is required so multi-review skips
   its interactive "Apply these fixes now?" prompt and proceeds straight to applying fixes —
   without it, this subagent has no human to answer and the loop stalls.

   Pass focus text targeting the gaps/changes from the previous round only — do NOT re-review
   the entire branch diff. The focus text for round 1 is empty (full review); for round N>1,
   the focus text is "<short description of what changed since round N-1, with file paths>".

   The /multi-review skill will save verbatim outputs from codex /review and /custom-review
   under tmp/multi-review/. It will also synthesize a merged review and produce per-reviewer
   A/B notes.

   Apply every finding regardless of severity. **Commit all fixes** with a clear semantic
   message and leave NO uncommitted changes — the next round diffs committed state only, so
   any uncommitted residue would be invisible to it. Do NOT push — no PR exists yet.
   Obey the comment-hygiene directive from step 3: never introduce task/PR/wave/plan
   labels into code or doc comments — describe the code, or cite a concrete `#NNN`/`ADR`.

   **TDD for fixes — when appropriate:** Before implementing a fix, decide whether a failing
   unit test should be written first. Add a test first when the finding describes a behavioral
   bug, an incorrect/missing branch, an off-by-one, a wrong output shape, a regression, a
   silent layer mismatch, or any other defect whose presence/absence can be expressed as a
   test assertion against a callable unit. Write the test, watch it fail for the right reason
   (i.e. the bug the finding describes — not a syntax error or import failure), then implement
   the fix and watch the test go green. Follow `superpowers:test-driven-development` for the
   red-green-refactor discipline.

   Skip the test-first step — do not shoehorn ceremony — when the fix is: a pure rename, a
   comment/docs edit, a formatting/lint change, a dead-code removal, a type-only tweak with
   no runtime effect, a config/build-script change with no unit-testable surface, a UI/visual
   change better verified by other means, or a finding already covered by an existing failing
   test you can point to. In each such case, briefly note in the commit message why a test
   was not added.

   Do NOT run a second review pass to confirm the fixes — the orchestrator decides whether
   to dispatch another round based on the pre-fix counts you report.

   Report back:
     - Counts of findings by severity, per reviewer (codex, custom-review) — counted from the
       *pre-fix* review output, before any fixes were applied.
     - The pre-fix critical count across both reviewers (explicit number).
     - For the comparison file: per-reviewer observations on accuracy (true vs false positives),
       depth (did they trace data flow / cite file:line / catch semantic gaps), and
       over/underrepresentation. Focus on what custom-review specifically did or missed
       compared to codex — this is the signal we want to amplify in the skill's future
       iterations.
     - Whether codex was available this round.
   ```

2. **After the subagent returns**, the orchestrator (this skill) does:
   - **Do NOT push.** Fixes stay local on the feature branch until Step 5 — that is what keeps CI from firing on intermediate review fixes.
   - **Append a round-N section** to `tmp/review-comparison.md`. Format (Markdown):

     ```markdown
     ## Round N — <ISO date>

     **Diff scope:** <files / focus text given to multi-review>
     **Codex available:** yes | no

     ### Per-reviewer scorecard

     | Reviewer | True positives | False positives | Missed (caught by other) | Depth notes |
     |---|---|---|---|---|
     | codex /review | … | … | … | … |
     | /custom-review | … | … | … | … |

     ### Actionable signal for custom-review improvement

     - <what custom-review missed that codex caught — specific finding + why it should have caught it>
     - <where custom-review over-flagged — what heuristic produced the noise>
     - <where custom-review outperformed codex — what to preserve / amplify>

     ### Critical count (pre-fix)

     <number across both reviewers>
     ```

   - **Print a chat summary** of each reviewer's performance for this round (2–4 sentences per reviewer, focusing on accuracy/depth/over-under).

3. **Stop condition:** if the pre-fix critical count for round N was 0, the loop ends immediately — the round's fixes are already committed, no further review is needed. Do not dispatch a verification round. Otherwise increment N and repeat.

Anti-rule: never dispatch round N+1 solely to confirm the fixes from round N landed cleanly. The next round only exists to surface new criticals; if round N's pre-fix already had none, there is nothing to confirm here.

If codex is unavailable on a given round, do not change the stop threshold here (unlike step 2) — multi-review's claude reviewer (custom-review) is still authoritative for the critical check.

## Step 5 — Push and open PR

The branch is now both implemented and review-clean (Step 4 exited with no pre-fix criticals). Push the branch. Open a PR with `gh pr create` (unsandboxable — `dangerouslyDisableSandbox: true`, never chained) against `<base>` (recorded in Branching). Title and body should follow the conventions in the user's global `CLAUDE.md`: semantic title, wrapped prose body explaining non-obvious trade-offs, test plan checklist, Claude Code attribution footer.

This push triggers the first — and ideally only — full CI run, on code that has already cleared the review gate.

Capture the PR number — the CI gate needs it.

## Step 6 — CI gate

**The PR does not merge until CI is green.** This is the second merge gate, independent of step 4: the multi-review loop trusts its own fixes and never watches the remote build, so a clean review can still sit on top of a red pipeline. Before handing off to cleanup, confirm the PR's head commit passes all required checks — and if it doesn't, fix it, the same way the earlier loops fix what their reviewers find.

**Stop rule:** Exit when all checks on the current PR head report success. If the repo has no checks at all, see "No CI configured" below.

Per round:

1. **Wait for CI on the latest head.** `gh` is unsandboxable — run it with `dangerouslyDisableSandbox: true`, never chained with other commands, capturing output to a file. Use:

   ```
   gh pr checks <num> --watch --interval 30
   ```

   `--watch` blocks until every check finishes, then exits 0 if all succeeded and non-zero if any failed or were cancelled. CI can take many minutes, so run the watch in the background (or with a generous timeout) rather than blocking the turn. Capture both the exit code and the listing (each check's state plus a details URL).

2. **Interpret the result:**
   - Exit 0 / every check `pass` → the gate is satisfied. Proceed to step 7 (cleanup).
   - Any check `fail` / `cancelled` / `timed_out` → CI is red. Dispatch the fix subagent below.
   - Checks still `pending` after `--watch` returns (rare — e.g. a required check that never reported) → treat as red and investigate the same way.

3. **Fix the failure (fresh subagent).** Dispatch a subagent whose sole job is to turn CI green:

   ```
   Round N — fix red CI on PR #<num>

   CI is failing. Identify and fix the cause so all required checks pass.

   1. List the failing checks and read their logs (gh is unsandboxable —
      dangerouslyDisableSandbox, never chained, capture to files):
        gh pr checks <num>                    (which checks failed + run URLs)
        gh run view <run-id> --log-failed     (the failing job's log)
   2. Reproduce locally where possible — run the same test / lint / build that the
      failing job runs.
   3. Fix the root cause, not the symptom. When the failure is a behavioral bug or a
      failing/flaky test, follow `superpowers:test-driven-development`: reproduce the
      failure locally first, fix, then watch it go green. For pure build/lint/format/
      config failures with no unit-testable surface, fix directly and note in the commit
      message why no test was added.
   4. Obey the comment-hygiene directive from step 3 — never introduce task/PR/wave/plan
      labels into code or doc comments.
   5. Commit with a clear semantic message. Do NOT push — the orchestrator pushes.

   Report back: the failing checks, the root cause, exactly what you changed, and whether
   the fix is a trivial infra/lint/flake/config change or a substantive behavioral change.
   ```

4. **Re-review substantive fixes — before pushing.** If the fix subagent reported a *substantive behavioral change* (anything beyond a lint/format/flake/config/infra fix), re-enter the Step 4 multi-review loop (`against <base>`, local) scoped to just those changes, iterating until its pre-fix critical count is 0 — a change large enough to alter behavior must also clear the no-criticals gate, or the two gates fall out of sync. The fix is already committed, so the loop diffs it correctly, and nothing is pushed during the re-review. Trivial infra/lint/flake/config fixes skip this step.

5. **Push the (now review-clean) head and re-watch.** The orchestrator pushes (`git push`) and returns to the top of this loop (the CI watch) to re-check CI on the new head. Because any substantive fix was re-reviewed in step 4 above before this push, CI never runs on un-reviewed code.

**No CI configured.** If `gh pr checks <num>` reports no checks for the head commit, there is no build to gate on. Log one line — `CI gate skipped: no checks reported for <sha>` — and proceed to step 7. Do not block waiting for checks that will never appear.

## Step 7 — Cleanup

Invoke the `cleanup` skill. It will merge the PR, delete the branch, sweep stale branches, and drain `SESSION.md`. By the time this runs, both merge-gate conditions (step 4 no-criticals, step 6 green CI) are satisfied.

## Reporting

End-of-turn summary (one or two sentences): the merged PR number, the branch, the number of plan-review rounds, local multi-review rounds (run before the PR opened), and CI-fix rounds, explicit confirmation that CI was green at merge, and the path to `tmp/review-comparison.md`.
