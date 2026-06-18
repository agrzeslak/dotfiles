---
name: plan-implement-merge
description: End-to-end pipeline that plans a change with superpowers, hardens the plan via a codex + plan-review-skill review loop, implements it test-driven via subagents, then hardens the implementation through a local multi-review loop until no critical findings remain, opens a review-clean PR, gates the merge on a green CI run, then runs cleanup. Use when the user invokes `/plan-implement-merge <description or path>` and wants the whole plan → review → implement → review → PR → merge pipeline run autonomously. Argument is auto-detected as a file path (if it resolves on disk) or treated as an inline description otherwise.
---

# Plan → Implement → Merge

Autonomous pipeline. Given a description or spec path, this skill plans, reviews the plan, implements TDD via subagents, iterates a local multi-review loop until clean, opens a review-clean PR, gates the merge on a green CI run, and cleans up. No iteration cap — the loops run until their stop conditions are met.

## Orchestrator model

The agent that runs this skill is the **orchestrator**. It does not do a step's heavy lifting itself; it dispatches a **fresh subagent per unit of work** and keeps its own context small and authoritative. That is the whole point of the structure: planning detail, implementation diffs, review outputs, and CI logs are bulky and would crowd out the orchestrator's judgment, so they live in subagents that read and write files and report back compact results.

**Durable state the orchestrator holds** (nothing else needs to survive between steps):

- the **target** — inline description or spec path;
- the **plan file path** (Step 1);
- the **feature branch** and **base branch** (Branching);
- the **PR number** (Step 5);
- per-loop **round counts** and the latest **pre-fix critical count** each round reported.

**The orchestrator's only jobs:**

- **Talk to the user.** Subagents are non-interactive, so every clarifying question, brainstorming exchange, and approval happens in the orchestrator. Never try to delegate interaction.
- **Dispatch and loop.** Spawn a step's subagent, read its compact report, apply the stop rule, decide whether to dispatch the next round.
- **Hold invariants** — above all, control when a push happens (below).
- **Trivial mechanics.** Context-free git/gh commands (branch create, push, capture the PR number, the CI watch) may run in the orchestrator directly; they carry no context cost. Anything that *reads or writes bulky content* goes to a subagent.

**Push invariant.** A push fires CI. To keep CI off intermediate work, **only two actions ever push:** opening the PR (Step 5) and re-pushing a CI fix after it has cleared review (Step 6). Every review/fix subagent **commits but never pushes**; the orchestrator performs the push.

**Two gates, sequential.** The PR is *opened* only after the multi-review loop reports no pre-fix criticals (Step 4) — that loop runs entirely on the local branch (`against <base>`), so no PR exists and no CI fires while review iterates. The PR then *merges* only once CI is green on its head (Step 6). The two stay independent — a clean AI review is not a passing build — but they no longer overlap on a live PR: review fully precedes the PR, so CI runs on already-reviewed code. The lone crossover is a *substantive* CI fix (Step 6), which re-enters the review gate locally before being pushed, so the gates never fall out of sync.

## Argument handling

The trailing text after `/plan-implement-merge` is the **target**. Auto-detect (orchestrator):

- If the trimmed argument resolves to an existing file or directory path, treat it as a **spec reference** — pass the path to the planning step verbatim and instruct the planner to read it.
- Otherwise treat the argument as an **inline description** of the work to do.

If the argument is empty, refuse with a short message asking for a description or path.

## Hard preconditions

The orchestrator runs these directly (they are light and produce part of the durable state). Refuse with a clear short message if any fail:

1. **Inside a git repository.**
2. **`gh` is on `PATH` and authenticated.** Run `command -v gh`; capture `gh auth status` output to a file (see [gh is unsandboxable](#gh-is-unsandboxable)).
3. **Required skills available:** `superpowers:brainstorming`, `superpowers:writing-plans`, `superpowers:test-driven-development`, `superpowers:subagent-driven-development`, `superpowers:verification-before-completion`, `plan-review-skill`, `multi-review`, `cleanup`. Check the available-skills list; refuse with the missing names if any are absent. Additionally, **if** the argument requests isolation (see Branching), also require `superpowers:using-git-worktrees` and refuse if absent — checking now avoids failing mid-run after planning has started.
4. **`codex` is on `PATH`.** Run `command -v codex`. If missing, refuse — codex is required for the plan-review loop (Step 2). In the multi-review loop (Step 4) codex is used *selectively*: multi-review's own codex gate auto-decides per round whether to spend codex's limited budget, so codex won't run every round — but it must still be installed so the gate can choose to use it.
5. **`multi-review` supports `--auto-apply`.** This pipeline runs `/multi-review` inside a subagent loop where no human is present to answer its "Apply these fixes now?" prompt. Confirm the installed `multi-review/SKILL.md` documents an `--auto-apply` control flag (grep for `--auto-apply`); refuse if absent so the operator can update the skill before relying on an autonomous loop that would otherwise stall.

## Branching

The orchestrator runs this directly. This skill normally runs serially, so worktrees are unnecessary. **Only** create a worktree if the argument explicitly says the work needs isolation (e.g., "in parallel", "isolated worktree", "while other work continues"); in that case invoke `superpowers:using-git-worktrees`.

Otherwise:

- If the current branch is the repo's default branch, create a new feature branch *before* planning. Derive the name from a short slug of the argument (e.g., `feat/<slug>`). Switch to it.
- If already on a non-default branch, continue on it.

Record the two values later steps need: the **feature branch** (just created, or the current non-default branch) and the **base branch** — the repo's default branch that Step 4 diffs against (`against <base>`) and that Step 5's PR targets. Derive the base once from the repo's default branch (e.g. `git symbolic-ref --short refs/remotes/origin/HEAD`, then strip the `origin/` prefix; fall back to `main`).

## Shared subagent conventions

Referenced by name from the steps below instead of being restated each time.

### Comment hygiene (include verbatim in every code-writing subagent prompt)

Every subagent that writes code or docs (Steps 3, 4, 6) must receive this block verbatim:

> The plan's task, PR, wave, and commit identifiers (e.g. `Task 4`, `PR 6`, `H2-PR-2`, `Lane J Task 17`) and the plan file name are orchestration scaffolding for this run — not documentation of the code. **Never carry them into code or doc comments.** Every comment must describe present behavior, intent, or rationale for a reader who never saw the plan. If a reference is genuinely load-bearing for an explanation, cite a durable, externally-resolvable handle — a concrete GitHub `#NNN` or `ADR NNNN` — never an internal task/PR/plan label. (This mirrors the "Comments describe the code, not the process that produced it" rule in the repo's `AGENTS.md`; defer to that file if it conflicts.)

This is the root-cause fix for process-reference leakage: the labels are salient in a subagent's context precisely because we hand it a numbered task, so the prohibition must travel with the task.

### TDD for fixes

When a review or CI subagent fixes a finding, it decides per-finding whether a failing test comes first:

- **Write the test first** when the finding is a behavioral defect expressible as an assertion against a callable unit — wrong/missing branch, off-by-one, wrong output shape, regression, silent layer mismatch, or a failing/flaky test. Watch it fail *for the right reason* (the bug the finding describes, not a syntax or import error), implement the fix, watch it go green. Follow `superpowers:test-driven-development`.
- **Skip the test** — do not shoehorn ceremony — for a pure rename, a comment/docs edit, a formatting/lint change, dead-code removal, a type-only tweak with no runtime effect, a config/build change with no unit-testable surface, a UI/visual change better verified otherwise, or a finding already covered by an existing failing test you can name. Briefly note in the commit message why no test was added.

### Critical-count stop rule (loop Steps 2 and 4)

A round reviews, then applies fixes (and, in Step 4, commits them). **Exit the loop the moment a round's pre-fix critical count is 0** — that round's fixes are trusted and already applied; any residue is caught by the next gate. The pre-fix critical count is the *only* gate; non-critical findings in an otherwise-clean round are applied and then the loop ends.

Severity is reviewer-assigned: trust the labels reviewers print. Treat `critical`, `blocking`, `P0`, or equivalent as critical; if a reviewer labels inconsistently, take the highest severity it assigned for that finding.

**Anti-rule:** never dispatch a follow-up round solely to confirm the previous round's fixes landed. A round exists only to surface *new* criticals; if the pre-fix count was already 0 there is nothing to confirm. Subagents therefore must **not** run a second review pass over their own fixes — they report pre-fix counts, and the orchestrator decides whether to dispatch the next round.

### gh is unsandboxable

Every `gh` invocation runs with `dangerouslyDisableSandbox: true`, is never chained with other commands, and captures its output to a file for subsequent sandboxed commands to read.

## Step 1 — Plan (orchestrator interacts; subagent writes the plan)

**Clarify the design first — questioning gate (orchestrator only; subagents can't ask).** The most common failure of this pipeline is skipping straight to planning because the request "seemed clear." It rarely is: a request that names a feature still leaves the user-facing behavior, the UI, and the non-obvious trade-offs unstated. **Unless the user opted out (below) or a spec file already settles every design decision, reaching the planning subagent without having asked a single question means you under-asked — stop and find the decisions.**

Surface every decision point that has more than one reasonable answer, prioritizing:

- **User-facing changes** — UI/layout, copy, interaction, defaults, and empty/error/edge-state behavior.
- **Non-obvious trade-offs** — wherever multiple valid approaches exist (data shape, sync vs async, where logic lives, migrate vs rewrite, scope boundaries).
- **Ambiguous scope / acceptance criteria** — what's in, what's out, what "done" means.

Before asking, skim the relevant code so your options, trade-offs, and context reflect the actual stack and conventions — not guesses. Then ask with the `AskUserQuestion` tool so each decision is a structured choice, not an open-ended prompt; batch related decisions into one call (it takes up to 4). Keep each question terse and skimmable. For every option give:

- **the option**, in a few words;
- a **recommendation** — put the recommended option first, mark it `(Recommended)`, and give the one-line *why*;
- the **trade-offs**, especially the non-obvious ones the user wouldn't think to weigh;
- **context** — the existing conventions, constraints, or prior art that bear on the choice.

For UI/layout decisions, use option `preview`s (ASCII mockups) so the user can compare designs visually. Keep asking — across rounds if needed — until you can restate the goal *and* the chosen approach back without hedging.

If scope is genuinely open-ended (a vague description with no settled shape), invoke `superpowers:brainstorming` first to explore, then run the questioning gate on the resulting design forks. Skip brainstorming when the argument points to a spec file that already encodes intent, or once the structured questions have pinned the design.

**The only way to skip the gate** is an explicit user opt-out for this run (e.g. "don't ask, just build it"). Then make the most reasonable calls and record each assumption in the intent brief so the choices stay visible.

**Persist intent.** Once intent is locked, write a concise intent brief to `tmp/plan-implement-merge/intent.md` (goal, approach, scope, acceptance criteria, constraints, edge cases). This hands the planning subagent clean context without replaying the dialogue.

**Dispatch the planning subagent.** Spawn a fresh subagent to run `superpowers:writing-plans` against the target plus the intent brief. Because no human is reachable inside the subagent, instruct it: if it hits a genuine ambiguity, make the most reasonable assumption and record it in the plan rather than stopping to ask. It produces the plan file and reports back the plan file path and a one-paragraph summary. **Capture and remember the plan file path** — every later step references it.

## Step 2 — Plan review loop

Orchestrator loops; each round is a fresh subagent. Stop per the [critical-count stop rule](#critical-count-stop-rule-loop-steps-2-and-4) on the **pre-fix** critical count.

Per round, dispatch one subagent:

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
    before any edits. Print the explicit critical count (and high count if codex was unavailable).
  - Do NOT run a second review to confirm your fixes — the orchestrator decides whether to
    dispatch another round based on the pre-fix counts you report.
```

After each report, look at the pre-fix critical count (and pre-fix high count if codex was unavailable). If it is 0, the loop is done — the round's fixes are already applied; exit immediately. Otherwise increment N and repeat. The codex-unavailable threshold raise above is specific to plan review: with only one reviewer left, gate on no-critical *and* no-high.

## Step 3 — Implement (TDD, subagent fan-out)

The plan is now hardened. Step 3 is itself a fan-out of subagents, which is even more granular than one-subagent-per-step: `superpowers:subagent-driven-development` dispatches a **fresh subagent per task**, and `superpowers:test-driven-development` is the methodology each task subagent follows (tests first, then implementation, then verify). The orchestrator runs the dispatch loop and retains only compact per-task summaries — all code lives in the task subagents — so this keeps the orchestrator's context clean by construction.

Follow the subagent-driven-development skill exactly for fan-out/serialization rules. Each task subagent receives the plan path, the specific task it owns, instructions to use TDD, and the [comment-hygiene](#comment-hygiene-include-verbatim-in-every-code-writing-subagent-prompt) block verbatim.

After all tasks complete, dispatch a verification subagent to run `superpowers:verification-before-completion` against the plan's acceptance criteria. If any verification fails, dispatch a fix-up subagent and re-verify — loop until every acceptance criterion passes.

## Step 4 — Multi-review loop (local, no PR)

**No PR exists yet.** This loop hardens the branch entirely on its local committed diff (`against <base>`), so it triggers no push, no `gh`, and no CI. The PR opens in Step 5 only once this loop is clean, so CI runs on already-reviewed code instead of on every intermediate fix — the whole point of doing review before the PR.

**Precondition — clean tree.** The `against <base>` target diffs *committed* changes only (`git diff <base>...HEAD`). Before the first round, ensure all of Step 3's implementation is committed and the working tree is clean; otherwise the first round's diff is incomplete. Each round's subagent commits its own fixes, so the tree stays clean between rounds and every round sees the full, accurate branch-vs-base change.

Orchestrator loops; each round is a fresh subagent. Stop per the [critical-count stop rule](#critical-count-stop-rule-loop-steps-2-and-4) on the **pre-fix** critical count across whichever reviewers ran.

Initialize `<repo root>/tmp/review-comparison.md` if it does not exist. It is a running cumulative log designed to drive **improvements to the claude reviewer (`custom-review`)** specifically — each entry should be actionable for future skill edits (what custom-review missed that codex caught, what it over-flagged, where its depth fell short of or exceeded codex).

Per round:

1. **Dispatch a fresh subagent:**

   ```
   Round N — multi-review of branch <feature-branch> against <base>

   Run `/multi-review against <base> --auto-apply`. The `against <base>` form selects the
   branch target — multi-review reviews the local committed diff `git diff <base>...HEAD`
   with no PR, no push, and no `gh`. The `--auto-apply` flag is required so multi-review skips
   its interactive "Apply these fixes now?" prompt and applies fixes directly — without it,
   this subagent has no human to answer and the loop stalls.

   Pass focus text targeting the gaps/changes from the previous round only — do NOT re-review
   the entire branch diff. Round 1's focus text is empty (full review); for round N>1 it is
   "<short description of what changed since round N-1, with file paths>".

   Do NOT pass --codex or --no-codex: let multi-review's codex gate auto-decide whether this
   change and this round warrant codex's limited budget. codex may legitimately be skipped
   (e.g. a doc/mechanical change, or a clean later round); that is expected, not a failure.
   The skill saves verbatim reviewer outputs under tmp/multi-review/, synthesizes a merged
   review, and — only when codex also ran — produces per-reviewer A/B notes.

   Apply every finding regardless of severity, following the TDD-for-fixes policy appended below.
   **Commit all fixes** with a clear semantic message and leave NO uncommitted changes — the
   next round diffs committed state only, so any residue would be invisible to it. Do NOT push
   — no PR exists yet. Obey the comment-hygiene directive appended below. Do NOT run a second
   review pass to confirm the fixes — the orchestrator decides whether to dispatch another round.

   Report back:
     - Counts of findings by severity, per reviewer that ran (custom-review always; codex only
       if the gate ran it) — from the *pre-fix* review output, before any fixes.
     - The pre-fix critical count across whichever reviewers ran (explicit number).
     - For the comparison file: per-reviewer observations on accuracy (true vs false positives),
       depth (did they trace data flow / cite file:line / catch semantic gaps), and
       over/underrepresentation — focused on what custom-review did or missed vs codex.
     - Whether codex ran this round; if not, the one-line reason multi-review printed
       (e.g. "skipped — round 2, prior round had 0 blocking findings").
   ```

   Before dispatching, append two blocks to that prompt verbatim, from [Shared subagent conventions](#shared-subagent-conventions): the **TDD for fixes** bullets and the **Comment hygiene** blockquote. Both sections are the canonical copy source — paste them as-is.

2. **After the subagent returns**, the orchestrator does (all from the compact report — no pushing):
   - **Append a round-N section** to `tmp/review-comparison.md`:

     ```markdown
     ## Round N — <ISO date>

     **Diff scope:** <files / focus text given to multi-review>
     **Codex ran:** yes | no (if no: <gate reason, e.g. "auto-skipped — clean round 2" / "unavailable">)

     ### Per-reviewer scorecard

     | Reviewer | True positives | False positives | Missed (caught by other) | Depth notes |
     |---|---|---|---|---|
     | codex /review | … | … | … | … |
     | /custom-review | … | … | … | … |

     (If codex was gate-skipped this round, fill its row with `skipped — <reason>` rather than
     counts — the A/B comparison only exists on rounds where codex actually ran.)

     ### Actionable signal for custom-review improvement

     - <what custom-review missed that codex caught — specific finding + why it should have caught it>
     - <where custom-review over-flagged — what heuristic produced the noise>
     - <where custom-review outperformed codex — what to preserve / amplify>

     ### Critical count (pre-fix)

     <number across both reviewers>
     ```

   - **Print a chat summary** of each reviewer's performance for this round (2–4 sentences per reviewer, focused on accuracy/depth/over-under).

3. **Stop** per the critical-count stop rule, then increment N and repeat if needed.

**Codex-unavailable handling differs from Step 2.** If codex did not run on a round — unavailable, or auto-skipped by multi-review's gate — do **not** raise the stop threshold here. multi-review's claude reviewer (custom-review) always runs and is authoritative for the critical check. A gate-skipped codex round means the gate judged the change low-stakes; trust that and gate on custom-review's pre-fix criticals as usual.

## Step 5 — Push and open PR

The branch is now implemented and review-clean (Step 4 exited with no pre-fix criticals). Per the push invariant, **the orchestrator pushes the branch** — this is the deliberate first push that triggers the first (and ideally only) full CI run, on code that has already cleared the review gate.

Then dispatch a subagent to author the PR and report back its number:

```
Open a PR for branch <feature-branch> against <base>.

Read the branch's commits/diff and run `gh pr create` (gh is unsandboxable —
dangerouslyDisableSandbox, never chained, capture output to a file) targeting <base>.
Title and body follow the conventions in the user's global CLAUDE.md: semantic title,
wrapped prose body explaining non-obvious trade-offs, a test-plan checklist, and the
Claude Code attribution footer.

Report back: the PR number and URL.
```

**Capture the PR number** — the CI gate needs it.

## Step 6 — CI gate

**The PR does not merge until CI is green.** This is the second merge gate, independent of Step 4: the multi-review loop trusts its own fixes and never watches the remote build, so a clean review can still sit on a red pipeline. Before cleanup, confirm the PR's head passes all required checks — and if it doesn't, fix it the same way the earlier loops fix what their reviewers find.

**Stop rule:** exit when all checks on the current PR head report success. If the repo has no checks at all, see "No CI configured" below.

Per round:

1. **Wait for CI on the latest head** (orchestrator — the watch carries no context cost). gh is unsandboxable; capture output to a file. Use:

   ```
   gh pr checks <num> --watch --interval 30
   ```

   `--watch` blocks until every check finishes, exiting 0 if all succeeded and non-zero if any failed or were cancelled. CI can take many minutes, so run the watch in the background (or with a generous timeout) rather than blocking the turn. Capture both the exit code and the listing (each check's state plus a details URL).

2. **Interpret the result:**
   - Exit 0 / every check `pass` → gate satisfied. Proceed to Step 7.
   - Any check `fail` / `cancelled` / `timed_out` → CI is red. Dispatch the fix subagent.
   - Checks still `pending` after `--watch` returns (rare — e.g. a required check that never reported) → treat as red and investigate the same way.

3. **Fix the failure (fresh subagent):**

   ```
   Round N — fix red CI on PR #<num>

   CI is failing. Identify and fix the cause so all required checks pass.

   1. List the failing checks and read their logs (gh is unsandboxable —
      dangerouslyDisableSandbox, never chained, capture to files):
        gh pr checks <num>                    (which checks failed + run URLs)
        gh run view <run-id> --log-failed     (the failing job's log)
   2. Reproduce locally where possible — run the same test / lint / build the failing job runs.
   3. Fix the root cause, not the symptom, following the TDD-for-fixes policy appended below.
   4. Obey the comment-hygiene directive appended below.
   5. Commit with a clear semantic message. Do NOT push — the orchestrator pushes.

   Report back: the failing checks, the root cause, exactly what you changed, and classify the
   fix as either *trivial* (lint/format/flake/config/infra, no change to runtime behavior) or
   *substantive* (alters logic, outputs, or behavior). When in doubt, classify as substantive.
   ```

   Before dispatching, append the **TDD for fixes** bullets and the **Comment hygiene** blockquote from [Shared subagent conventions](#shared-subagent-conventions) to that prompt verbatim.

4. **Re-review substantive fixes — before pushing.** If the fix subagent reported a *substantive behavioral change* (anything beyond a lint/format/flake/config/infra fix), re-enter the Step 4 multi-review loop (`against <base>`, local) scoped to just those changes, iterating until its pre-fix critical count is 0 — a change large enough to alter behavior must also clear the no-criticals gate, or the two gates fall out of sync. The fix is already committed, so the loop diffs it correctly, and nothing is pushed during the re-review. Trivial fixes skip this step; if the subagent's classification is unclear or you doubt it, treat the fix as substantive and re-review — a redundant local review is cheap next to merging unreviewed behavior.

5. **Push the (now review-clean) head and re-watch.** The orchestrator pushes (`git push`) and returns to the top of this loop. Because any substantive fix was re-reviewed in step 4 above before this push, CI never runs on un-reviewed code.

**No CI configured.** If `gh pr checks <num>` reports no checks for the head commit, there is no build to gate on. Log one line — `CI gate skipped: no checks reported for <sha>` — and proceed to Step 7. Do not block waiting for checks that will never appear.

## Step 7 — Cleanup

Invoke the `cleanup` skill **in the orchestrator** (not a subagent): it is the final step, so context cost is moot, and it may need to interact (e.g. SESSION.md triage). It merges the PR, deletes the branch, sweeps stale branches, and drains `SESSION.md`. By the time this runs, both merge-gate conditions (Step 4 no-criticals, Step 6 green CI) are satisfied.

## Reporting

End-of-turn summary (one or two sentences): the merged PR number, the branch, the number of plan-review rounds, local multi-review rounds (run before the PR opened), and CI-fix rounds; explicit confirmation that CI was green at merge; and the path to `tmp/review-comparison.md`.
