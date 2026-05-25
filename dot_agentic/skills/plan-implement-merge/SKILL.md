---
name: plan-implement-merge
description: End-to-end pipeline that plans a change with superpowers, hardens the plan via a codex + plan-review-skill review loop, implements it test-driven via subagents, opens a PR, drives a multi-review iteration loop until no critical findings remain, then runs cleanup. Use when the user invokes `/plan-implement-merge <description or path>` and wants the whole plan → review → implement → PR → review → merge pipeline run autonomously. Argument is auto-detected as a file path (if it resolves on disk) or treated as an inline description otherwise.
---

# Plan → Implement → Merge

Autonomous pipeline. Given a description or spec path, this skill plans, reviews the plan, implements TDD via subagents, opens a PR, iterates multi-review until clean, and cleans up. No iteration cap — the loops run until their stop conditions are met.

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

Record the chosen branch name; later steps need it.

## Step 1 — Plan

**Before doing anything else in this step: ask me questions until what we want to implement and how is unambiguously clear.** Drive the conversation interactively — surface ambiguities in scope, acceptance criteria, constraints, data shapes, edge cases, and the intended approach, and keep asking until you can restate the goal and the approach back without hedging. Only proceed to brainstorming/planning once that bar is met. (If the user has explicitly told you to skip clarifying questions for this run, honor that and make the most reasonable call instead.)

Invoke `superpowers:brainstorming` first if the argument is an inline description that lacks concrete scope. Skip brainstorming when the argument points to a spec file that already encodes intent, or when the description is unambiguous.

Then invoke `superpowers:writing-plans` to produce the implementation plan. Forward the argument (description or path) as the source material. Let writing-plans choose the plan file path; capture and remember that path — every later step references it.

## Step 2 — Plan review loop

**Stop rule (read this first):** A round runs a review and then applies fixes. Exit the loop as soon as a round's **pre-fix** findings contain no criticals. Do **not** dispatch a follow-up round to verify the fixes from the previous round — the fixes are trusted, and any residual issues are caught later by step 5. The pre-fix critical count is the *only* gate; non-critical findings in a clean round are applied and then the loop ends without another review.

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

Follow the subagent-driven-development skill exactly for fan-out/serialization rules. Each subagent receives the plan path, the specific task it owns, and instructions to use TDD.

After all tasks complete, run `superpowers:verification-before-completion` against the plan's acceptance criteria before moving on. If any verification fails, dispatch a fix-up subagent and re-verify.

## Step 4 — Push and open PR

Push the branch. Open a PR with `gh pr create` (unsandboxable — `dangerouslyDisableSandbox: true`, never chained). Title and body should follow the conventions in the user's global `CLAUDE.md`: semantic title, wrapped prose body explaining non-obvious trade-offs, test plan checklist, Claude Code attribution footer.

Capture the PR number — the next step needs it.

## Step 5 — Multi-review loop

**Stop rule (read this first):** A round runs `/multi-review` (which itself runs three reviewers and applies fixes) and then pushes. Exit the loop as soon as a round's **pre-fix** critical count across all reviewers is 0. Do **not** dispatch a follow-up round to verify the fixes from the previous round — the fixes are trusted. The pre-fix critical count is the *only* gate; non-critical findings in a clean round are applied, pushed, and then the loop ends without another review.

Initialize `<repo root>/tmp/review-comparison.md` if it does not exist. The file is a running cumulative log designed to drive **improvements to `custom-review2`** specifically — each entry should be actionable for future skill edits (what custom-review2 missed, what it over-flagged, where its depth fell short of codex or custom-review, where it outperformed them).

Per round:

1. **Dispatch a fresh subagent** with the goal:

   ```
   Round N — multi-review of PR #<num>

   Run `/multi-review PR #<num> --auto-apply` (the `PR #` prefix is required — multi-review's
   target parser recognizes `PR #N`, `#N`, or a PR URL; a bare number is **not** parsed as a
   PR and would default the target to `uncommitted`). The `--auto-apply` flag is required so
   multi-review skips its interactive "Apply these fixes now?" prompt and proceeds straight
   to applying fixes — without it, this subagent has no human to answer and the loop stalls.

   Pass focus text targeting the gaps/changes from the previous round only — do NOT re-review
   the entire PR. The focus text for round 1 is empty (full review); for round N>1, the focus
   text is "<short description of what changed since round N-1, with file paths>".

   The /multi-review skill will save verbatim outputs from codex /review, /custom-review, and
   /custom-review2 under tmp/multi-review/. It will also synthesize a merged review and
   produce per-reviewer A/B notes.

   Apply every finding regardless of severity. Commit fixes with a clear semantic message.

   Do NOT run a second review pass to confirm the fixes — the orchestrator decides whether
   to dispatch another round based on the pre-fix counts you report.

   Report back:
     - Counts of findings by severity, per reviewer (codex, custom-review, custom-review2) —
       counted from the *pre-fix* review output, before any fixes were applied.
     - The pre-fix critical count across all reviewers (explicit number).
     - For the comparison file: per-reviewer observations on accuracy (true vs false positives),
       depth (did they trace data flow / cite file:line / catch semantic gaps), and
       over/underrepresentation. Focus on what custom-review2 specifically did or missed
       compared to the other two — this is the signal we want to amplify in the skill's
       future iterations.
     - Whether codex was available this round.
   ```

2. **After the subagent returns**, the orchestrator (this skill) does:
   - **Push** the commits the subagent made: `git push`.
   - **Append a round-N section** to `tmp/review-comparison.md`. Format (Markdown):

     ```markdown
     ## Round N — <ISO date>

     **Diff scope:** <files / focus text given to multi-review>
     **Codex available:** yes | no

     ### Per-reviewer scorecard

     | Reviewer | True positives | False positives | Missed (caught by others) | Depth notes |
     |---|---|---|---|---|
     | codex /review | … | … | … | … |
     | /custom-review | … | … | … | … |
     | /custom-review2 | … | … | … | … |

     ### Actionable signal for custom-review2 improvement

     - <what custom-review2 missed that the others caught — specific finding + why it should have caught it>
     - <where custom-review2 over-flagged — what heuristic produced the noise>
     - <where custom-review2 outperformed — what to preserve / amplify>

     ### Critical count (pre-fix)

     <number across all reviewers>
     ```

   - **Print a chat summary** of each reviewer's performance for this round (2–4 sentences per reviewer, focusing on accuracy/depth/over-under).

3. **Stop condition:** if the pre-fix critical count for round N was 0, the loop ends immediately — the round's fixes are already pushed, no further review is needed. Do not dispatch a verification round. Otherwise increment N and repeat.

Anti-rule: never dispatch round N+1 solely to confirm the fixes from round N landed cleanly. The next round only exists to surface new criticals; if round N's pre-fix already had none, there is nothing to confirm here.

If codex is unavailable on a given round, do not change the stop threshold here (unlike step 2) — multi-review's two claude reviewers are still authoritative for the critical check.

## Step 6 — Cleanup

Invoke the `cleanup` skill. It will merge the PR, delete the branch, sweep stale branches, and drain `SESSION.md`.

## Reporting

End-of-turn summary (one or two sentences): the merged PR number, the branch, the number of plan-review and multi-review rounds, and the path to `tmp/review-comparison.md`.
