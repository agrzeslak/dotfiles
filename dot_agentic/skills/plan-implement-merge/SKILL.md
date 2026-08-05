---
name: plan-implement-merge
description: End-to-end pipeline that plans a change with superpowers, hardens the plan via a codex + plan-review-skill review loop, implements it test-driven via subagents, then hardens the implementation through a local multi-review loop that runs until its review coverage converges, opens a review-clean PR, gates the merge on a green CI run, then runs cleanup. Use when the user invokes `/plan-implement-merge <description or path>` and wants the whole plan → review → implement → review → PR → merge pipeline run autonomously. Argument is auto-detected as a file path (if it resolves on disk) or treated as an inline description otherwise.
---

# Plan → Implement → Merge

Autonomous pipeline. Given a description or spec path, this skill plans, reviews the plan, implements TDD via subagents, iterates a local multi-review loop until its review coverage converges, opens a review-clean PR, gates the merge on a green CI run, and cleans up. No iteration cap and no count thresholds — each review loop runs until no unreviewed surface is left that is worth another round (see the [convergence stop rule](#convergence-stop-rule-loops-in-steps-2-4-and-6)).

## Orchestrator model

The agent that runs this skill is the **orchestrator**. It does not do a step's heavy lifting itself; it dispatches a **fresh subagent per unit of work** and keeps its own context small and authoritative. That is the whole point of the structure: planning detail, implementation diffs, review outputs, and CI logs are bulky and would crowd out the orchestrator's judgment, so they live in subagents that read and write files and report back compact results.

**Durable state the orchestrator holds** (nothing else needs to survive between steps):

- the **target** — inline description or spec path;
- the **plan file path** (Step 1);
- the **feature branch** and **base branch** (Branching);
- the **PR number** (Step 5);
- per review loop, a **coverage ledger** — one compact entry per round recording: the gap that round was dispatched against, the surface and angles it examined, the gaps its findings opened (each with the finding that evidences it), the surface its own fixes rewrote, which reviewers ran / failed / degraded, and per-reviewer severity counts. Round 1 records the changed-region (or plan-section) inventory; later rounds record only **deltas** — fix code added, angles opened or closed — so the ledger stays small. The counts are for `tmp/review-comparison.md`, not for the stop decision.

**The orchestrator's only jobs:**

- **Talk to the user.** Subagents are non-interactive, so every clarifying question, brainstorming exchange, and approval happens in the orchestrator. Never try to delegate interaction.
- **Dispatch and loop.** Spawn a step's subagent, read its compact report, apply the stop rule, decide whether to dispatch the next round.
- **Hold invariants** — above all, control when a push happens (below).
- **Trivial mechanics.** Context-free git/gh commands (branch create, push, capture the PR number, the CI watch) may run in the orchestrator directly; they carry no context cost. Anything that *reads or writes bulky content* goes to a subagent.

**Push invariant.** A push fires CI. To keep CI off intermediate work, **only two actions ever push:** opening the PR (Step 5) and re-pushing a CI fix after it has cleared review (Step 6). Every review/fix subagent **commits but never pushes**; the orchestrator performs the push.

**Two gates, sequential.** The PR is *opened* only after the multi-review loop converges — no unreviewed surface left that is worth another round (Step 4) — and that loop runs entirely on the local branch (`against <base>`), so no PR exists and no CI fires while review iterates. The PR then *merges* only once CI is green on its head (Step 6). The two stay independent — a converged AI review is not a passing build — but they no longer overlap on a live PR: review fully precedes the PR, so CI runs on already-reviewed code. The lone crossover is a *substantive* CI fix (Step 6), which re-enters the review gate locally before being pushed, so the gates never fall out of sync.

Gate 1 is a **judgment**, not an arithmetic check, and it is deliberately not the last line of defense: gate 2's CI and the human review of the PR both come after it. That is what licenses the loop to stop while a reviewer would still, given another round, say something.

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
6. **The installed `multi-review` runs `code-review` alongside `custom-review`.** Grep the same `multi-review/SKILL.md` for `code-review`. If absent, do **not** refuse — the loop still works on one claude reviewer — but print one line saying the review gate will run with a single claude reviewer this run, so a round that covered fewer angles is never mistaken for a converged one. Step 4's round prompt asks for per-reviewer coverage and counts that an older `multi-review` cannot supply; this is where that mismatch is caught, rather than in a confusing subagent report.

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

### Convergence stop rule (loops in Steps 2, 4, and 6)

A round reviews, then applies every finding regardless of severity (and, in Steps 4 and 6, commits them). The round itself never decides anything: the orchestrator reads the round's report and decides whether to dispatch another.

**Why a count can never be the gate.** Each round reviews code — or a plan — that the *previous round just wrote*. Reviewers will label something critical on any nontrivial fresh diff, so a nonzero per-round finding count is the **steady state of a healthy loop**, not evidence of an unhealthy branch. Rounds manufacture their own successors, and a count-based gate therefore has no fixed point; it forces rounds long past the point where they buy anything. What genuinely runs out is **surface** — the regions and angles a review can still examine. Surface is the only quantity here that decreases, so it is the one the stop rule tracks.

**The rule.** Continue only while **named** unreviewed-or-under-reviewed surface remains. A gap is one of exactly two things:

- **Unreviewed region** — surface the work materially changed that no round has examined: the branch's changed code in Steps 4 and 6, the plan's sections in Step 2. This includes what a round's own fixes just wrote or rewrote, when those were broad enough to constitute new surface.
- **Under-reviewed angle** — surface that *was* examined, but not for the question a prior round's finding evidenced. One finding about a single call site can reveal that the whole error path was never traced: that path is covered by file and uncovered by question.

**No gap ⇒ stop, unconditionally.** A namable gap is *necessary* to continue and never *sufficient*: once one exists, weigh whether covering it is worth the round (see Calibration and Tiebreak). Nothing buys a round when no gap can be named — not a critical count, not a reviewer's insistence, not unease.

**Guard — gaps are evidenced, never invented.** Angles are infinitely enumerable in the abstract, so "we haven't examined X through lens Y" would license unlimited rounds. A gap counts only if it is anchored in the work itself (changed surface, never examined) or in a prior round's *actual* finding. An angle the orchestrator thought up on the spot is not a gap.

**Coverage is a closed inventory, not an open question.** Never ask a round "what did you not examine?" — asked open-endedly, a reviewer always returns a non-empty list, and that becomes a fresh engine for endless rounds, exactly the failure this rule replaces. The inventory is bounded and shrinking instead: round 1 is a *full* review, so it closes out the changed-region list; after that the only additions are the fix code later rounds write and the angles their findings evidence. Dispatch against named entries in the coverage ledger, nothing else.

**Calibration — stakes set the bar for "sufficiently reviewed".** How crucial and complex the reviewed component is determines how thoroughly its surface must be covered before it counts as done; it is not an independent round budget. A small, low-stakes component's surface is covered by one pass — one round is a legitimate whole loop. A security-sensitive or intricate one warrants more angles over the same surface. This is the orchestrator reading what it is reviewing; there is no caller flag for it.

**Converged looks like this:** rounds landing on the same surface through the same angles, nothing novel — reviewers circling, residue that is preference, phrasing, or taste.

**Tiebreak, for marginal calls only.** When a gap exists but its value is unclear, price the *actual* next round (rounds after the first are gap-scoped and cheaper than round 1) against what the later gates catch anyway: Step 6's CI and the human review of the PR. These settle a close call. They never outvote a genuine gap, and they never manufacture one.

**A confirmation round is not a thing.** "The fixes landed" is never itself a reason to spend a round, and subagents must **not** review their own fixes — they report, the orchestrator decides. A sweep over fix code is justified by the fixes' *breadth* (broad fixes are new surface), never by wanting to verify them.

**A failed review is not a converged one.** If a round produced no usable review — Step 4's both-claude-reviewers-failed case — its surface went unexamined, so the rule already says re-dispatch. Never read a missing review as an empty gap list.

**One-line rationale, either way.** Print the decision and its reason whether continuing or stopping. Symmetric friction matters: if only stopping required an argument, continuing would stay free and the loop would drift back into running forever. Continuing names the gap; stopping names the saturation.

**Severity labels still get recorded, but they are not a stop input.** Severity is reviewer-assigned: trust the labels reviewers print, and where a reviewer labels inconsistently take the highest severity it assigned that finding. Counts feed `tmp/review-comparison.md`'s scorecard (Step 4), whose purpose is improving `custom-review`. Do not re-derive a count gate from them.

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

Orchestrator loops; each round is a fresh subagent. Stop per the [convergence stop rule](#convergence-stop-rule-loops-in-steps-2-4-and-6). The surface here is the plan's sections, decisions, and risks; the angles are the lenses reviewers apply to them (`plan-review-skill`'s VP Product / VP Engineering / VP Design are three distinct angles over the same surface).

One wrinkle specific to plan review: a round's fixes *rewrite the plan*, and a restructured section is proportionally far more new surface than a code fix is. Expect that to legitimately buy rounds here that it would not buy in Step 4 — and expect a round to name it.

Per round, dispatch one subagent:

```
Round N — plan review

Plan file: <path>
Gap this round covers: <the gap named from the ledger; for round 1, the whole plan>
Already examined: <the ledger's one-line surface/angle entries from prior rounds; empty for round 1>

Run these reviews in parallel:
  1. codex `/review` against the plan file. Save output to tmp/plan-implement-merge/round-N/codex.md.
  2. `/plan-review-skill` against the plan file. Save output to tmp/plan-implement-merge/round-N/plan-review.md.
  3. Generic extension point (no-op unless the repo opts in): only if the repo defines a local
     gate-check skill (`.claude/skills/gate-check/SKILL.md` exists at the repo root) — any repo
     may provide one supporting a plan mode that takes the plan path and returns a findings
     report — execute that skill in plan mode against the plan file, reading its SKILL.md and
     following it exactly. Save its report to tmp/plan-implement-merge/round-N/gate-check.md.
     Its findings carry binding-source citations (e.g. ADR / living doc / budget pin) and
     ready-to-apply `plan-change:` lines; preserve both when merging. It is one more angle over
     the plan's surface, and gaps its findings open count like any reviewer's. A repo without the
     skill is unaffected — skip this step silently.

If codex fails or reports usage exhaustion, continue with plan-review-skill alone and say so in
your report — do not change how you review. A round with one reviewer covered fewer angles than a
round with three; that is a coverage fact the orchestrator needs, not a reason for you to work
differently.

Merge findings. Apply every finding regardless of severity by editing the plan file in place.

Report back:
  - **Coverage:** which plan sections/decisions you examined, and through which angles. For round 1
    treat this as the plan's section inventory, marking each section examined or not.
  - **Gaps your findings opened:** any part of the plan that a finding implies was never examined
    for the question that finding raises — each named together with the finding that evidences it.
    Report ONLY gaps anchored in an actual finding or in plan surface you did not reach. Do not
    produce an open-ended "things I didn't cover" list; speculative gaps are not wanted and will
    be ignored.
  - **Surface you rewrote:** which sections your applied fixes materially restructured — a rewritten
    section is new surface a later round may need to examine.
  - Whether codex ran successfully; any reviewer that failed, and which angles were lost with it.
  - Counts of findings by severity, per reviewer that ran (codex when it ran; plan-review-skill
    always; the repo-local gate-check reviewer when the repo defines one) — from the *pre-fix*
    review output, before any edits. These are for the record, not for the stop decision.
  - Do NOT run a second review to confirm your fixes — the orchestrator decides whether to
    dispatch another round.
```

After each report, append the round's entry to the plan-review coverage ledger and apply the convergence stop rule: continue only against a named gap the report evidences — an unexamined section, a section the round's own fixes restructured, or an angle a finding pointed at. If the report names none, the loop is done; the round's fixes are already applied. Print the one-line rationale either way, then increment N and repeat if continuing.

Losing codex is a coverage fact, not a threshold change: it means fewer angles were applied to the plan this round. That may itself be the named gap for one more round with the remaining reviewer — but only if the plan's stakes warrant re-examining surface that has already been read once. It never automatically buys a round.

## Step 3 — Implement (TDD, subagent fan-out)

The plan is now hardened. Step 3 is itself a fan-out of subagents, which is even more granular than one-subagent-per-step: `superpowers:subagent-driven-development` dispatches a **fresh subagent per task**, and `superpowers:test-driven-development` is the methodology each task subagent follows (tests first, then implementation, then verify). The orchestrator runs the dispatch loop and retains only compact per-task summaries — all code lives in the task subagents — so this keeps the orchestrator's context clean by construction.

Follow the subagent-driven-development skill exactly for fan-out/serialization rules. Each task subagent receives the plan path, the specific task it owns, instructions to use TDD, and the [comment-hygiene](#comment-hygiene-include-verbatim-in-every-code-writing-subagent-prompt) block verbatim.

After all tasks complete, dispatch a verification subagent to run `superpowers:verification-before-completion` against the plan's acceptance criteria. If any verification fails, dispatch a fix-up subagent and re-verify — loop until every acceptance criterion passes.

## Step 4 — Multi-review loop (local, no PR)

**No PR exists yet.** This loop hardens the branch entirely on its local committed diff (`against <base>`), so it triggers no push, no `gh`, and no CI. The PR opens in Step 5 only once this loop converges, so CI runs on already-reviewed code instead of on every intermediate fix — the whole point of doing review before the PR.

**Precondition — clean tree.** The `against <base>` target diffs *committed* changes only (`git diff <base>...HEAD`). Before the first round, ensure all of Step 3's implementation is committed and the working tree is clean; otherwise the first round's diff is incomplete. Each round's subagent commits its own fixes, so the tree stays clean between rounds and every round sees the full, accurate branch-vs-base change.

Orchestrator loops; each round is a fresh subagent. Stop per the [convergence stop rule](#convergence-stop-rule-loops-in-steps-2-4-and-6). The surface here is the branch's changed regions; the angles are the questions reviewers ask of them. Round 1 is a full review, which closes out the region inventory — so from round 2 on, the only gaps that can exist are the fix code earlier rounds wrote and the angles their findings evidenced.

Initialize `<repo root>/tmp/review-comparison.md` if it does not exist. It is a running cumulative log designed to drive **improvements to `custom-review`** specifically — the one reviewer in the roster that is ours to edit. Each entry should be actionable for future skill edits: what `custom-review` missed that a peer reviewer caught, what it over-flagged, where its depth fell short of or exceeded the peers. Its peers are the built-in `/code-review` (every round) and codex (when multi-review's gate spends the budget), so **every** round yields comparison data now, not only codex rounds.

Per round:

1. **Dispatch a fresh subagent:**

   ```
   Round N — multi-review of branch <feature-branch> against <base>

   Gap this round covers: <the gap named from the coverage ledger; for round 1, the full diff>
   Already examined: <the ledger's one-line surface/angle entries from prior rounds; empty for round 1>

   Run `/multi-review against <base> --auto-apply`. The `against <base>` form selects the
   branch target — multi-review reviews the local committed diff `git diff <base>...HEAD`
   with no PR, no push, and no `gh`. The `--auto-apply` flag is required so multi-review skips
   its interactive "Apply these fixes now?" prompt and applies fixes directly — without it,
   this subagent has no human to answer and the loop stalls.

   Focus text is **the gap named above**, verbatim in substance — not a generic diff of what
   changed since the last round. Round 1's focus text is empty (full review, which closes out
   the region inventory). For round N>1 the gap may be a region (the fix code an earlier round
   wrote) or an angle spanning surface already read once (e.g. "trace the error path across all
   touched files — round 2's finding at foo.rs:88 shows it was never examined"). When the gap is
   an angle, you SHOULD look at previously-reviewed files: that is the point. What you must not
   do is re-review the whole diff from scratch for no named reason.

   Codex: by default do NOT pass --codex or --no-codex — let multi-review's gate auto-decide
   whether this change and this round warrant codex's limited budget. codex may legitimately be
   skipped (e.g. a doc/mechanical change, or a quiet later round); that is expected, not a
   failure. The single exception is stated in the "Gap this round covers" line above: when the
   gap is an angle the standing claude roster structurally does not ask, that line will say
   "force --codex" — pass it then and only then. codex is not extra surface, it is an extra
   angle, so one deliberately thicker round beats several thin repeats.

   The two claude reviewers — /custom-review and the built-in /code-review — are ungated and
   run in parallel every round, so a codex-skipped round is still a multi-reviewer round.
   The skill saves verbatim reviewer outputs under tmp/multi-review/, synthesizes a merged
   review, and writes per-reviewer comparison notes for whichever reviewers ran.

   Do NOT try to invoke /code-review yourself, and do not "help" if multi-review's nested
   call fails: it is user-invocable only, so the Skill tool refuses it and the nearest listed
   skill (custom-review) gets run instead — which silently turns two reviewers into one
   duplicated one. multi-review owns that invocation.

   Apply every finding regardless of severity, following the TDD-for-fixes policy appended below.
   **Commit all fixes** with a clear semantic message and leave NO uncommitted changes — the
   next round diffs committed state only, so any residue would be invisible to it. Do NOT push
   — no PR exists yet. Obey the comment-hygiene directive appended below. Do NOT run a second
   review pass to confirm the fixes — the orchestrator decides whether to dispatch another round.

   Report back:
     - **Coverage:** which changed regions you examined and through which angles. For round 1 —
       the full review — give this as the branch's changed-region inventory (file, and the area
       within it), marking each region examined or not; that inventory is what later rounds are
       measured against, so make it complete. Derive it from `git diff --stat <base>...HEAD` plus
       the file:line anchors in the reviewer outputs under tmp/multi-review/ — multi-review does
       not emit an inventory of its own.
     - **Gaps your findings opened:** any surface a finding implies was never examined for the
       question that finding raises — each named with the finding (file:line) that evidences it,
       and whether covering it needs an angle the claude reviewers structurally do not ask.
       Report ONLY gaps anchored in an actual finding or in changed surface you did not reach.
       Do not produce an open-ended "things I didn't cover" list: speculative gaps will be
       ignored, and inventing them would keep this loop running forever.
     - **Surface your fixes wrote:** the files/regions your applied fixes materially changed, and
       whether that constitutes new surface (a broad behavioral rewrite) or not (a one-line
       guard, a rename, a comment).
     - Counts of findings by severity, per reviewer that ran (custom-review and code-review
       always; codex only if the gate ran it; the repo-local gate-check reviewer when the repo
       defines one — multi-review runs it automatically) — from the *pre-fix* review output,
       before any fixes. code-review ships no severity labels of its own, so report the
       severities multi-review assigned its findings in the merge, plus its CONFIRMED/PLAUSIBLE
       split. These are for the comparison log, not for the stop decision.
     - For the comparison file: per-reviewer observations on accuracy (true vs false positives),
       depth (did they trace data flow / cite file:line / catch semantic gaps), and
       over/underrepresentation — focused on what custom-review did or missed vs its peers.
       Separate misses forced by a peer's *structure* (code-review's finding cap, its effort
       level, codex getting no focus text) from misses that reflect judgment; only the latter
       says anything about reviewer quality.
     - The effort level code-review ran at, and whether it ran the agent fan-out or degraded to
       a single inline pass.
     - Whether codex ran this round; if not, the one-line reason multi-review printed
       (e.g. "skipped — round 2, prior round had 0 blocking findings").
     - Any reviewer that failed, with multi-review's one-line reason.
   ```

   Before dispatching, append two blocks to that prompt verbatim, from [Shared subagent conventions](#shared-subagent-conventions): the **TDD for fixes** bullets and the **Comment hygiene** blockquote. Both sections are the canonical copy source — paste them as-is.

2. **After the subagent returns**, the orchestrator does (all from the compact report — no pushing):
   - **Append a round-N section** to `tmp/review-comparison.md`:

     ```markdown
     ## Round N — <ISO date>

     **Gap covered:** <the gap this round was dispatched against; round 1 = full diff>
     **Codex ran:** yes | no (if no: <gate reason, e.g. "auto-skipped — quiet round 2" / "unavailable">)
     **code-review:** <level> · <fan-out | single-pass> | failed — <reason>

     ### Per-reviewer scorecard

     | Reviewer | True positives | False positives | Missed (caught by peer) | Structural misses | Depth notes |
     |---|---|---|---|---|---|
     | /custom-review | … | … | … | … | … |
     | /code-review | … | … | … | … | … |
     | codex /review | … | … | … | … | … |

     (Fill a reviewer's row with `skipped — <reason>` or `failed — <reason>` instead of counts
     when it did not produce a usable review. Codex's row is `skipped` on most rounds by design;
     the /custom-review vs /code-review comparison exists on every round.)

     ### Actionable signal for custom-review improvement

     - <what custom-review missed that a peer caught — specific finding, which peer, and why
       custom-review should have caught it (name the angle or verification step it lacks)>
     - <where custom-review over-flagged — what heuristic produced the noise>
     - <where custom-review outperformed its peers — what to preserve / amplify>

     ### Coverage

     **Examined this round:** <regions / angles>
     **Gaps opened by findings:** <gap — evidencing finding at file:line> | none
     **Surface the fixes wrote:** <regions — new surface | not new surface>
     **Severity counts (pre-fix, per reviewer):** <for the record, not a stop input>

     ### Decision

     continue — <the named gap this buys a round for> | stop — <what saturated>
     ```

   - **Append the round's entry to the coverage ledger** (orchestrator state, deltas only after round 1).
   - **Print a chat summary** of each reviewer's performance for this round (2–4 sentences per reviewer, focused on accuracy/depth/over-under).

3. **Decide** per the convergence stop rule, print the one-line rationale, then increment N and repeat if a gap was named and is worth covering. When the named gap is an angle the claude reviewers structurally do not ask, put `force --codex` in the next round's "Gap this round covers" line — one thicker round instead of several thin ones.

**Reviewer coverage is an input to the gap question, never a threshold.** Step 2's old codex rule raised the bar when a reviewer was missing; nothing like that exists here, in either loop.

- **Codex auto-skipped by multi-review's gate** — the common case, and a judgment that the change is low-stakes. Trust it. Not a gap on its own.
- **Codex unavailable, or `code-review` alone failed** — one angle less was applied this round. That is a coverage fact to record, and it can only buy a round if it leaves a *named* gap the remaining reviewers plainly did not cover, weighed against the component's stakes. `custom-review` remains the load-bearing reviewer.
- **Both claude reviewers failed** — the round examined nothing. Not a converged round; re-dispatch the same gap.

## Step 5 — Push and open PR

The branch is now implemented and review-clean (Step 4's loop converged — no unreviewed surface left worth a round). Per the push invariant, **the orchestrator pushes the branch** — this is the deliberate first push that triggers the first (and ideally only) full CI run, on code that has already cleared the review gate.

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

**The PR does not merge until CI is green.** This is the second merge gate, independent of Step 4: the multi-review loop trusts its own fixes and never watches the remote build, so a converged review can still sit on a red pipeline. Before cleanup, confirm the PR's head passes all required checks — and if it doesn't, fix it the same way the earlier loops fix what their reviewers find.

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

4. **Re-review substantive fixes — before pushing.** If the fix subagent reported a *substantive behavioral change* (anything beyond a lint/format/flake/config/infra fix), re-enter the Step 4 multi-review loop (`against <base>`, local) scoped to just those changes, running it under the [convergence stop rule](#convergence-stop-rule-loops-in-steps-2-4-and-6) — a change large enough to alter behavior is new surface and must be examined, or the two gates fall out of sync. The fix is already committed, so the loop diffs it correctly, and nothing is pushed during the re-review. This re-review starts with a small, sharply-bounded surface — one round usually covers it, and it converges as soon as the fix's own regions have been examined and its findings opened no further gap. Trivial fixes skip this step entirely; if the subagent's classification is unclear or you doubt it, treat the fix as substantive and re-review — one local round is cheap next to merging unreviewed behavior.

5. **Push the (now review-clean) head and re-watch.** The orchestrator pushes (`git push`) and returns to the top of this loop. Because any substantive fix was re-reviewed in step 4 above before this push, CI never runs on un-reviewed code.

**No CI configured.** If `gh pr checks <num>` reports no checks for the head commit, there is no build to gate on. Log one line — `CI gate skipped: no checks reported for <sha>` — and proceed to Step 7. Do not block waiting for checks that will never appear.

## Step 7 — Cleanup

Invoke the `cleanup` skill **in the orchestrator** (not a subagent): it is the final step, so context cost is moot, and it may need to interact (e.g. SESSION.md triage). It merges the PR, deletes the branch, sweeps stale branches, and drains `SESSION.md`. By the time this runs, both merge-gate conditions (Step 4's review converged, Step 6's CI green) are satisfied.

## Reporting

End-of-turn summary (one or two sentences): the merged PR number, the branch, the number of plan-review rounds, local multi-review rounds (run before the PR opened), and CI-fix rounds; **each review loop's stop rationale — what surface saturated**; explicit confirmation that CI was green at merge; and the path to `tmp/review-comparison.md`.
