---
name: pim
description: Lightweight plan → implement → merge pipeline. Takes a feature description, a pointer to where one lives, or a ready-made plan. Without a plan it questions the operator until the ask is understood (especially the non-obvious trade-offs), writes a plan, and hardens it with one repo-grounded review pass; with a plan it goes straight to implementation. Then it loops `/custom-review` — orchestrator triaging which findings are worth fixing — verifies locally, opens a PR, waits for CI to go green, merges with the repo's own convention, and cleans up. Every plan, review, implementation, and fix runs in a subagent whose model tier the orchestrator picks. Use when the operator invokes `/pim <description | path | plan>`.
---

# pim — plan → implement → merge

Ship one change end to end: plan, harden the plan, implement, harden the code, merge. The small
sibling of `plan-implement-merge` — one reviewer instead of three, orchestrator-triaged fixes
instead of apply-everything, no reviewer-comparison bookkeeping. Escalate to that skill when the
change wants a second instrument on the same code: codex's outside model, or `code-review`'s finder
fan-out, which catches removed-guard regressions `custom-review` reads past.

## Orchestrator

The agent running this skill orchestrates and never plans, reviews, or writes code itself. Plan text,
diffs, and review output live in subagents so the orchestrator's judgment stays uncrowded.

**Durable state** — write it to `<artifacts dir>/ledger.md` as you go, so an interrupted run is
resumable:

- **target** and **mode** (`plan-supplied` or `plan-from-description`);
- **tier profile**;
- **artifacts dir** — `<origin repo root>/tmp/pim/<run-slug>/`, resolved *before* entering the
  worktree so artifacts outlive it;
- **worktree path**, **feature branch**, and two distinct base values: the **base ref** for every diff
  and review (`origin/<default>`) and the **base branch name** for the PR (`<default>`);
- **plan path** — `<artifacts dir>/plan.md` in both modes (Step 2 puts it there when pim wrote the
  plan; the preflight copies it there when the operator supplied one), unless the repo tracks plan
  documents (Step 2);
- **PR number**;
- **round ledger** — one line for the plan pass and one per code-review round: surface reviewed, the
  **HEAD sha that round reviewed** (a region round in Step 6 needs it), findings raised, which were
  fixed, which were rejected and why, gaps opened.

**Jobs:** talk to the operator (subagents cannot ask), pick tiers, dispatch rounds, triage findings,
apply the stop rule, own every push. Context-free git and `gh` calls may run inline.

**Push invariant.** A push fires CI, so exactly two actions push: opening the PR (Step 7) and
re-pushing a CI fix (Step 8). Every subagent commits and never pushes.

## Argument

Trailing text after `/pim` is the target; empty → refuse, asking for a description, path, or plan. A
path that resolves is read and classified, and **the verdict printed in one line** before work starts
— `Target: docs/spec-foo.md — a spec; planning from it.` Misclassification is cheap to catch here,
expensive later, and the operator is the only one who can catch it.

- **Plan** — ordered tasks with concrete file paths and acceptance criteria → mode `plan-supplied`;
  skip Steps 1–3. A supplied plan is assumed already hardened, typically by an earlier pim run.
  **Resolve its path to absolute and copy it to `<artifacts dir>/plan.md` before entering the
  worktree.** A relative path resolves against a different cwd once `EnterWorktree` moves the session,
  and a path inside the origin repo is outside the worktree entirely — either way the run's first
  dispatch would read the wrong file or nothing at all.
- **Spec** — prose stating what is wanted, no task decomposition → mode `plan-from-description`.
- **A directory** → a spec reference for the planner to read. **Anything that does not resolve** → an
  inline description. Both are `plan-from-description`.

## Tier profile (print it)

Three roles take a model: **planner**, **reviewer**, and **implementer/fixer** — *fixer* being whoever
applies a finding the orchestrator selected, to the plan (Step 3), the code (Step 6), or a red build
(Step 8). Fixers sit with implementers because the thinking is already done: the reviewer proved the
defect and named its consequence, the orchestrator ruled it worth fixing, and a bounded edit is what
remains.

| Profile | When | Planner / reviewer | Implementer / fixer |
|---|---|---|---|
| `standard` | the default | `opus` | `sonnet` |
| `hard` | real ambiguity remains, the change is intricate, or it is security- or data-integrity-sensitive | `opus` | `opus` |
| `trivial` | small, mechanical, low-stakes — a rename, a doc edit, a config tweak, one file with obvious semantics | `sonnet` | `sonnet` |

Skim the target and the code it touches, assign one profile, and **print it with its reason** so the
operator can interrupt. Pass the tier as each `Agent` dispatch's `model`. Re-assess once when the plan
exists — a plan thornier than its description moves `standard` → `hard` — but judge it from the
planner's own reported summary and tier recommendation, never by opening the plan: that read is the one
thing the orchestrator's context cannot afford. Say so in one line when the profile moves.

**Per-dispatch escalation.** A single fix dispatch may run at `opus` while the profile stays put, for
one of these reasons and no others, because "when in doubt" quietly becomes always-`opus`:

- the fix is **not localized** — it spans layers, modules, or call sites that must stay consistent;
- the reviewer proved the **defect but not a safe remedy**, so fixing needs a design decision;
- the surface is **security-, data-integrity-, concurrency-, or migration**-sensitive;
- the single plan-fix dispatch faces a finding demanding a **restructure** rather than a correction;
- the diagnosis is **not legible from the available evidence** — a CI log that does not explain its own
  failure is the common case, and guessing is how a two-strikes budget gets spent.

Escalate the dispatch, not the profile, and print the reason.

## Preconditions and degraded modes

**Refuse on a missing skill only when this run will actually invoke it.** `custom-review` is always
required — it is pim's only reviewer and nothing covers for it. `superpowers:writing-plans` is required
only in `plan-from-description` mode; a supplied plan never invokes it. `cleanup` is required only when
the run can reach a merge, so the no-git-repo path below does not need it. Refusing a run pim could
complete is its own failure. Everything else pim carries itself: the implementation discipline lives in
the blocks below rather than in a dependency, so there is no degraded implementation mode.

Everything else degrades, and **which capability is lost depends on which piece is missing** — probe
all three, then print one line naming the case:

| Missing | Still runs | Skipped |
|---|---|---|
| Not a git repo (`git rev-parse --git-dir`) | plan, implement, review via custom-review's `paths` target over the changed files | worktree, branch, commits, PR, CI, merge, cleanup |
| Git repo, no remote (`git remote`) | worktree off the local default branch, commits, review `against <base>` | PR, CI, merge |
| `gh` missing or unauthenticated (`command -v gh`; `gh auth status` to a file) | everything local, including the push | PR, CI, merge |

Example: `Skipped PR/CI/merge/cleanup: not a git repository; changes are in the working tree.`
Skill-authoring directories and scratch trees are not repos — this path is real, not hypothetical.

**The no-git substitution, stated once for every dispatch that needs it.** Any prompt in this file that
opens with `<branch> against <base>` instead names the changed files, and drops every instruction that
assumes commits — "everything committed", a ref-range target, "commits but never pushes". Steps 5 and 6
both invoke this; a step added later invokes it too rather than reinventing the wording.

`gh` is unsandboxable per the global instructions: `dangerouslyDisableSandbox: true`, never chained
with other commands, output captured to a file. Trailing `;` on any command with a pipe or redirect.

## Worktree

Create the artifacts dir first — `<origin repo root>/tmp/pim/<run-slug>/`, slug from the target —
because it must outlive the disposable worktree.

`EnterWorktree` and `ExitWorktree` are deferred tools: load them with
`ToolSearch("select:EnterWorktree,ExitWorktree")`. `EnterWorktree` with a name from the same slug
moves the session's cwd into the worktree, so every later subagent inherits it with no path plumbing.
Skip it in two cases: the session is already in a worktree (reuse it), or there is no git repo (work
in place).

**Resolve the base yourself rather than inferring it from the tool, and keep two values.**
`EnterWorktree` branches from `origin/<default branch>` under the default `worktree.baseRef: fresh`, but
a `head` setting branches from local HEAD instead — and a wrong base silently mis-scopes every review
and the PR.

- **base ref** — `git symbolic-ref --short refs/remotes/origin/HEAD`, kept **whole** as
  `origin/<default>`. Every diff and every review target uses this. Do **not** strip the `origin/`
  prefix: the local branch of the same name is usually behind the remote, and diffing against a stale
  local ref silently pulls everyone else's recent commits into the review — which then surface in Step
  5 as `extra:` work nobody on this branch wrote.
- **base branch name** — the same value with `origin/` stripped, used only for `gh pr create --base`
  and `gh pr merge`.

Confirm the worktree really sits on the base ref with `git merge-base --is-ancestor <base ref> HEAD`.
If that fails, `EnterWorktree` branched from somewhere else; take the real base from `git merge-base`
against the branch you started from and record it.

## Stop rule — diminishing returns (Step 6)

The code-review loop stops on the orchestrator's judgment, never on a finding count. A count cannot
terminate: each round reviews what the last round wrote, so nonzero findings are the steady state of a
healthy loop. What runs out is **surface**. (Step 3 is a single pass and needs no stop rule.)

**Continue only while a named gap exists.** A gap is exactly one of:

- **unreviewed surface** — something the work materially changed that no round has examined, including
  an earlier round's fix code when it was broad enough to count;
- **under-reviewed angle** — surface that was examined, but not for the question a *real prior
  finding* evidenced. One bad call site can show a whole error path was never traced.

A gap is necessary and never sufficient: weigh covering it against what the later gates catch anyway —
local verification, CI, and the human reading the PR. **No gap means stop, unconditionally**: not a
critical count, not a reviewer's insistence, not unease.

**Gaps are evidenced, never invented.** Never ask a round "what did you not examine?" — asked
open-endedly, a reviewer always answers, which is an engine for infinite rounds. Gaps come from round
1's inventory or from an actual finding. A **rejected** finding is a decision, not unreviewed surface,
and buys nothing. A **failed** round examined nothing, so re-dispatch its gap rather than reading
failure as convergence.

**Stakes set thoroughness**, not a round budget: one round is a legitimate whole loop for a small,
low-stakes change; an intricate or security-sensitive one warrants more angles over the same surface.

**Print the decision either way** — continuing names the gap, stopping names what saturated. Symmetric
friction, or "one more round" stays free.

## Triage (orchestrator, plan pass and code loop)

Reviewers report; the orchestrator decides. **Fix** correctness and behavioral defects, silent
mismatches between layers, anything that makes the code or UI state a falsehood, misses against the
plan's acceptance criteria, and **work no task asked for** — Step 5's `extra:` answers. Unrequested code
is a defect even when it is correct: it was never planned, never reviewed against a requirement, and is
now yours to maintain. Remove it, or record why it had to stay. **Reject** preference, phrasing, taste,
speculative future-proofing,
and any finding whose cited evidence does not hold up. Record every rejection with its reason in
`<artifacts dir>/ledger.md` — an unrecorded rejection gets re-litigated every round. Real findings
that are out of this change's scope go to `SESSION.md` per the repo convention, not into the loop.

## Two strikes on any fix-and-retry loop

Three loops retry a fix against the same failing signal: acceptance criteria (Step 5), the repo's own
checks (Step 7), and red CI (Step 8). Each stops after the **second** failed attempt on the same failure
and goes to the operator with the evidence. Two failures on one signal mean the diagnosis is wrong, not
that the fix needs another try — and unlike the review loops, nothing else downstream bounds these.

## Blocks to paste verbatim

### Comment hygiene — every code- or doc-writing subagent

> The plan's task, PR, wave, and commit identifiers (e.g. `Task 4`, `PR 6`, `H2-PR-2`) and the plan
> file name are orchestration scaffolding for this run — not documentation of the code. **Never carry
> them into code or doc comments.** Every comment must describe present behavior, intent, or rationale
> for a reader who never saw the plan. If a reference is genuinely load-bearing, cite a durable handle
> — a concrete GitHub `#NNN` or `ADR NNNN` — never an internal task/PR/plan label.

### TDD policy — every implementation and fix subagent

> **Write the test first** when the change is a behavioral defect or feature expressible as an
> assertion against a callable unit — a wrong or missing branch, an off-by-one, a wrong output shape, a
> regression, a flaky test.
>
> Watch each step. The new test must **fail for the reason you expect** — one that passes immediately is
> testing existing behavior, so fix the test, not the code. Once it fails correctly, write the minimal
> code to pass it; if it still fails, fix the code, not the test. Whole suite green before you commit.
>
> **Skip the test** — do not manufacture ceremony — for a pure rename, a comment or docs edit,
> formatting or lint, dead-code removal, a type-only change with no runtime effect, a config or build
> change with no unit-testable surface, or a finding an existing failing test already covers (name it).
> **That list is exhaustive.** If the change is not on it, the test comes first; "this one is too small
> to test" is not on the list, and reaching for it means writing the test.
>
> A change that is neither unit-assertable nor on the skip list — cross-service wiring, a shell script, a
> layout-only change — still gets **verified**, by the cheapest means that actually exercises it: an
> integration test, a scripted command with expected output, a recorded manual check. Say in the commit
> message which you used. What is never acceptable is shipping it unverified because no unit test fits.
>
> Note in the commit message why no test was added.

### Implementer conduct — every implementation and fix subagent

> **No human is reachable from here.** On a genuine ambiguity, make the most reasonable call, record it
> in your report and in the commit message, and keep going — never stall waiting to ask.
>
> One clear responsibility per file, following the file structure the plan defines. If a file you are
> writing grows past the plan's intent, do not split it on your own — report that as a concern. In
> existing code, follow established patterns and improve what you touch the way a good developer would,
> but do not restructure anything outside your task.
>
> Report `DONE`, or `DONE_WITH_CONCERNS` followed by the concerns themselves. Saying "this is too hard
> for me" is always acceptable and is not a failure — bad work is worse than no work.
>
> Commit with semantic messages. **Never push.**

## Step 1 — Question the operator (`plan-from-description` only)

Subagents cannot ask, so every question happens here. **Unless the operator opted out for this run
("don't ask, just build it"), reaching Step 2 without having asked anything means you under-asked** — a
request that names a feature still leaves its behavior and its trade-offs unstated.

Skim the relevant code first so the options reflect the actual stack, then use `AskUserQuestion`,
batching related decisions, on:

- **user-facing behavior** — UI, copy, defaults, and the empty / error / edge states;
- **non-obvious trade-offs** — where several valid approaches exist: data shape, sync vs async, where
  logic lives, extend vs rewrite, scope boundaries;
- **scope and acceptance criteria** — what is in, what is out, what "done" means.

Recommend an option first and say why in one line; give the trade-offs the operator would not think to
weigh and the convention or prior art bearing on the choice; use `preview` mockups for layout. Keep
asking, across rounds if needed, until you can restate the goal *and* the chosen approach without
hedging.

If the ask is genuinely shapeless, explore before questioning: one question at a time, build up a design
with the operator, restate it for agreement, then run the structured questions on the forks that remain.
Do this inline. `superpowers:brainstorming` covers the same ground but its terminal steps fight this
pipeline — it writes **and commits** a design doc into the repo, and its stated terminal state is to
invoke `writing-plans` itself, which would pull plan authoring into the orchestrator's context and
duplicate Step 2.

Write the locked intent to `<artifacts dir>/intent.md` — goal, approach, scope, acceptance criteria,
constraints, edge cases, and every assumption made under an opt-out. The planner reads that, not the
dialogue.

## Step 2 — Plan (subagent, planner tier)

Dispatch one subagent to invoke `superpowers:writing-plans` against the target plus
`<artifacts dir>/intent.md`. Tell it no human is reachable: on a genuine ambiguity, make the most
reasonable call and record it in the plan rather than stalling. It reports the plan path — the skill
writes to `docs/superpowers/plans/YYYY-MM-DD-<feature>.md` — and a one-paragraph summary.

**Two things in that skill point at an executor pim does not use, and both must be neutralized.** pim
owns execution (Step 4), and nobody inside a subagent can answer a prompt.

- Its **execution handoff** asks the operator to choose between subagent-driven and inline execution.
  Tell the planner to stop once the plan is written and reviewed, and report the path instead of
  offering options.
- Its **mandatory plan header** carries the line `REQUIRED SUB-SKILL: Use
  superpowers:subagent-driven-development … to implement this plan task-by-task`. Left in place, that
  directive reaches every implementer through the plan and the briefs, telling them to invoke a skill
  pim deliberately dropped — which either errors on a missing skill or starts a nested per-task review
  loop. Tell the planner to omit that line, and have the brief-builder strip any surviving
  invoke-an-execution-skill directive.

**The plan does not get committed.** It is scaffolding for this run — the same reason the comment
hygiene block keeps run labels out of the code — and a merged plan goes stale immediately, then
misleads whoever finds it. So **move** it out of the worktree into `<artifacts dir>/plan.md` (do not
copy: an untracked file left in `docs/superpowers/plans/` would either dirty the tree Step 6 needs
clean, or get swept into a commit by an implementer) and pass that path onward. Everything downstream
reads the plan from the artifacts dir.

The exception is a repo that **already tracks plan documents** — existing committed plans under
`docs/plans/`, `docs/superpowers/plans/`, or similar. Then follow the repo's convention over pim's:
leave the plan in place and let it be committed, exactly as with the merge method in Step 9.

Then re-assess the tier profile.

## Step 3 — Plan review: exactly one pass (skipped in `plan-supplied`)

**One critic, one fixer, then implement. Never a second round** — this is a hard cap, not a stop-rule
judgment. Two reasons it holds:

- `writing-plans` already looped its own reviewer, up to three iterations, over the plan as a
  *document* — completeness, spec alignment, decomposition, buildability — without ever opening the
  repo. This pass adds the one axis that gate structurally cannot: is the plan **right about this
  codebase**. That axis is worth one pass; the document gate is worth none.
- A second round was only ever bought by the fixer's own restructuring counting as new surface — a
  recursion with no floor, on an artifact nobody ships. Surviving plan defects are caught downstream:
  implementers record the assumptions they had to make, Step 5 verifies the acceptance criteria and
  catches work no task asked for, and Step 6's reviewer reads the plan as claims about the branch.

**The critic** (reviewer tier, read-only):

```
Plan review — the only pass. Plan: <artifacts dir>/plan.md
Intent brief: <artifacts dir>/intent.md

Review the plan against the repo it will be implemented in — read the code it names. Judge:
correctness of the approach for this codebase, risks and failure modes, conflicts with existing
conventions or prior art, work the codebase implies that the plan omits, and acceptance criteria
that cannot actually be checked here. Verify every file path and symbol the plan cites exists.

Do NOT re-review completeness, placeholders, spec alignment, or task decomposition as document
properties — `writing-plans`' own reviewer already gated those. Flag one of them only when reading
the code shows it is wrong (e.g. a task's boundary is impossible because the two files are coupled).

There is no second pass, so cover the whole plan now rather than pacing yourself.

Write your findings to <artifacts dir>/plan-review.md, then reply with, and only with:
  - a numbered findings list — one line each: severity, plan section, the claim, and the concrete
    consequence of leaving it;
  - Coverage: which sections you examined, and any you could not judge without information you did
    not have — name what was missing, since nothing downstream will revisit it.
Do not edit the plan.
```

Then a **fixer** (implementer/fixer tier, at `opus` when a finding demands restructuring rather than
correcting) gets the selected findings verbatim and edits the plan in place, reporting what it changed.

**The fixer's scope is the selected findings and nothing more.** With no second pass, an unrequested
rewrite would ship unreviewed. If the findings genuinely invalidate the plan's shape — the approach is
wrong for the codebase, not merely mis-specified — that is not a fix: re-run Step 2 with what the critic
found folded into the intent brief, or hand it back to the operator. Say which you did.

## Step 4 — Implement (subagents, implementer tier)

**Brief-builder first — one dispatch, planner tier.** It reads the plan **once** and writes one small
self-contained brief per task to `<artifacts dir>/briefs/task-NN.md`: that task's own text, the shared
preamble it depends on, the files it touches, and its acceptance criteria. It omits house rules the
blocks above already carry. It returns the ordered task list.

**Ordering constraint:** the brief-builder runs *after* Step 3's fixer, never before — that fixer's
edits would leave any earlier section map stale. In `plan-supplied` mode there is no Step 3, so it is
simply the run's first dispatch.

Why briefs rather than the plan path or pasted task text: plans run 1400+ lines, so handing each
implementer the file costs five or six full reads per run, while pasting task text would pull the plan
into the orchestrator's own context — the one most worth protecting. One full read plus N small briefs
avoids both.

**Briefs are for implementers only.** Step 5's conformance pass and Step 6's reviewer read the plan
itself: it stays the authoritative artifact, and a review judging the branch against a derived brief
could pass code that satisfies the brief while missing the plan.

**Then the dispatch loop, which the orchestrator runs itself** — dispatching is its job. One fresh
subagent per task, **in plan order and serially**, because every task shares one worktree and
concurrent writers would collide. Keep only compact per-task summaries.

Each implementer gets its brief path, its tier, and the **TDD policy**, **comment hygiene**, and
**implementer conduct** blocks verbatim. **Not the plan path** — the brief is meant to be complete, and
"here is the plan too, for reference" is read as permission, which puts all N full reads straight back.
If a brief is missing something, the implementer says so in its report rather than reading around it;
that is a brief-builder defect worth knowing about.

One axis is deliberately uncovered: **quality** — reuse, simplification, dead abstraction — because
`custom-review` promotes only proof-gated correctness findings. Run `/simplify` if that starts to bite.

## Step 5 — Conformance and acceptance (one dispatch, reviewer tier)

Two questions in one dispatch: they share their inputs — the whole diff and the plan — and both exist to
distrust what the implementers reported about their own work. This is also the only thing that catches an
implementer building **more** than was asked: `custom-review` passes unrequested-but-correct code, an
acceptance check sees only its criteria, and plan-as-claims sees only unmet obligations.

```
Conformance and acceptance — branch <feature branch> against <base>
Plan: <plan path> (the plan itself, not the task briefs)

Do not trust the implementers' reports; read the code. Answer the conformance questions FIRST, one
line per task, and state absence explicitly rather than omitting it:

  Task NN — missing: none | <what was requested and is not there>
            extra:   none | <what was built that no task asked for, at file:line>
            misunderstood: none | <requirement implemented as something else>

Then, per acceptance criterion in the plan: met or not met, with the command you ran or the
observation that shows it. Run the commands; do not infer.

Report BOTH sections even when a criterion fails — a failing command must not truncate the
conformance answers.
```

**Degraded mode:** apply the no-git substitution from Preconditions. Both question sets stay unchanged —
conformance and acceptance are what this pass is for, and neither needs git.

Fix what the orchestrator selects with a fix subagent (same tier rules, same three blocks), then
re-verify **only the criterion or task that failed** — not the whole dispatch, whose value was reading
diff and plan once. Two strikes applies; a criterion that fails twice usually means the plan is wrong
about the codebase. Leave the tree clean and everything committed; the review loop reviews committed
state.

## Step 6 — Code review loop

A review dispatch per round, plus a fix dispatch when the orchestrator selects findings. Stop per the
stop rule.

**Round N reviewer** (reviewer tier):

```
Round N — code review of branch <feature branch> against <base>
Plan: <plan path> — outside the diff by default, so custom-review will not discover it on its own.
Do NOT pass the plan path as custom-review's target argument: an explicit file path there selects its
`paths` target, which reviews statically with no diff at all, and a mixed target makes the skill stop
to ask a clarifying question no one can answer. Read it yourself instead, and how much depends on the
round:
  - ROUND 1 — sweep the whole plan. Treat it as claims about the code shipping against it: an
    obligation the plan states and the branch does not meet is a finding, not a coverage note. Say
    the sweep is done, so no later round repeats it.
  - LATER ROUNDS — read only the plan sections the named gap implicates. Re-reading the whole plan
    every round is a flat cost that defeats the point of narrowing the target.
Gap this round covers: <named gap; for round 1, the full diff>
Already examined: <ledger's one-line entries; empty for round 1>

Invoke the `custom-review` skill via the Skill tool. The target depends on this round:
  - round 1, and any round whose gap is an ANGLE: `against <base>` — an angle only means something
    over the whole surface;
  - a round whose gap is a REGION (fix code an earlier round wrote): `against <sha>`, where <sha> is
    **the HEAD the previous round reviewed** — the ledger records it — i.e. the commit *before* that
    round's first fix commit. Not the commit that closed the round: `against <x>` diffs `<x>...HEAD`,
    so passing the round's final commit yields an empty diff and custom-review refuses outright.
    A correct region target stops the round paying full-diff price for surface it was not dispatched
    against. If the skill refuses a sha in that position, fall back to `against <base ref>` and say so
    in your report;
  - degraded mode (no git repo): the changed file paths, which selects custom-review's `paths` target.
When a gap is named above, append it verbatim as trailing focus text; the skill reads that as an
`Additional focus:` directive.

The skill writes into tmp/custom-review-<timestamp>/ inside the worktree. Those artifacts are
review output, not deliverables: never commit them, and never use `git add -A` or `git add .` in
this repo — stage only the files you deliberately changed.

Let the skill write to its own tmp/custom-review-<timestamp>/ directory — it will not write outside
that directory, so do not redirect it. Then copy its review.md to <artifacts dir>/code-round-N.md.

Reply with, and only with:
  - REVIEW_PATH=<absolute path to the review.md the skill wrote>
  - a numbered findings list — one line each: severity, file:line, the claim, the concrete impact.
    Do not paraphrase the review body beyond these lines;
  - Coverage: the review's Coverage footer, condensed — surfaces examined, residual risk, test gaps;
  - Open questions: the review's Open Questions, one line each. These are high-risk uncertainties
    the proof gate would not pass as findings — candidate gaps, not fixes;
  - anything the review reports as skipped or unreachable.
Do not fix anything. Do not run a second review to check the first.
```

Two properties of `custom-review` shape this loop:

- **Coverage is stated, not inferred.** Surfaces examined, residual risk, and test gaps come from the
  review's own footer, so the stop rule reads a declared inventory rather than one reconstructed from
  `git diff --stat` and file:line anchors.
- **Focus biases; it does not narrow — the target does.** A named gap steers falsification, but the
  broad pass still reruns over whatever the target covers, which is why a region round narrows the
  *target* instead and pays only for the commits it was sent to examine. Round 1's Coverage footer stays
  the inventory later rounds are measured against, and an angle round re-covers read surface
  deliberately. Narrowing the target narrows the **claim surface, not what the reviewer may read** —
  `custom-review` reads the repo freely regardless of target, so producer-to-effect-site tracing
  survives. Expect fewer rounds than `plan-implement-merge` takes.

Findings arrive proof-gated — condition, wrong behavior, and impact at `file:line`, each link re-read —
so triage is mostly *fix now versus defer to `SESSION.md`* rather than *believe or reject*. A finding
whose evidence still does not hold on inspection is a rejection worth recording, since it also says
something about `custom-review` itself.

The **fix subagent** (implementer/fixer tier, escalated per dispatch when a named reason applies) gets
the selected findings verbatim, the **TDD policy**, **comment hygiene**, and **implementer conduct**
blocks, and: leave nothing
uncommitted, and do not re-review your own fixes.
It reports what it changed and whether that is broad enough to count as new surface.

**A refused review is a failed round.** `custom-review` refuses on an empty diff, and on a PR target
whose local branch is ahead or diverged. Neither should happen here — Step 5 leaves everything
committed and this loop reviews a local branch — but if one does, fix the cause and re-dispatch the
same gap rather than reading the refusal as convergence.

## Step 7 — Verify locally, then open the PR

Once the loop converges, dispatch one subagent (implementer/fixer tier) to detect and run the repo's own checks — tests, lint,
type-check, build, whatever it actually defines (`Makefile`, `justfile`, `package.json` scripts,
`cargo test`, CI config) — reporting each as pass or fail with the failing output, and pushing nothing.
Fix failures with a fix subagent and re-run, under the two-strikes rule. If the repo defines no checks,
say so in one line and continue. This runs once per run rather than per round: it catches most red-CI
cases at zero CI cost without putting a full test run on every review round.

Then the **orchestrator pushes** — the run's first push, on code that has already cleared review — and
dispatches a subagent (implementer/fixer tier) to open the PR: read the branch's commits and run `gh pr create` against
`<base>` with a semantic title, a wrapped body explaining the non-obvious trade-offs, a test-plan
checklist, and the Claude Code attribution footer. Capture the PR number.

## Step 8 — CI gate

The PR does not merge on a red build, and a converged review is not a passing build.

1. **Let the checks register first.** `--watch` waits for known checks to finish, not for checks to
   appear, and a freshly pushed head usually has none yet. Poll `gh pr checks <num>` until at least one
   check is listed, for up to ~3 minutes. Only if nothing has registered by then is this repo genuinely
   check-less (step 3).
2. **Watch** (orchestrator, background, generous timeout): `gh pr checks <num> --watch --interval 30`,
   output to a file. Exit 0 means every check passed.
3. **Still no checks after the settle window** → print `CI gate skipped: no checks reported for <sha>`
   and go to Step 9. Never block on checks that will never appear — but never treat "not yet
   registered" as "none exist", which would merge a branch whose CI was never evaluated.
4. **Any failure** → dispatch a fix subagent (implementer/fixer tier, escalated per dispatch when a
   named reason applies): read the failing logs — `gh pr checks
   <num>`, `gh run view <run-id> --log-failed`, each captured to a file — reproduce locally, fix the
   root cause under the **TDD policy**, **comment hygiene**, and **implementer conduct** blocks. It applies the same test the code loop's fix
   subagents apply — **is this new surface by the stop rule?** — and reports *trivial* (lint, format,
   flake, config, infra: not new surface) or *substantive* (broad enough to count), defaulting to
   substantive. One test, two names, so the CI loop and the review loop cannot disagree about the same
   diff.
5. A **substantive** fix is new surface: run one Step 6 round with that fix as its named focus before
   pushing, so the two gates never fall out of sync. Trivial fixes skip this.
6. The orchestrator pushes and returns to 1, under the two-strikes rule.

## Step 9 — Merge, leave the worktree, clean up

**pim decides *when* to merge; `cleanup` owns *how*.** That skill's Step 1 already merges the PR,
already picks the method from what the repo allows (preferring squash), and already composes the squash
subject and body from the PR title and body so GitHub does not concatenate every branch commit subject.
Do not restate that algorithm here — a second copy would drift, and pim's copy would be the worse one.

pim still issues the merge itself, for a worktree reason: `cleanup` finds the PR from the *current*
branch, and it refuses to delete the branch or worktree it is running in. So:

1. **Merge** with `gh pr merge <num>`, following `cleanup`'s Step 1 method rule. Print which method it
   selected and why. Leave branch deletion to `cleanup`, so one step owns it.
2. **If the merge is refused** — branch protection wanting a human review, a required check pim cannot
   satisfy — stop and hand the PR to the operator with the reason, exactly as `cleanup` does. Never
   reach for `--admin`: bypassing a protection rule is the operator's call, not pim's.
3. **Leave the worktree** — `ExitWorktree` with `action: "keep"` returns the session to the origin repo.
   Running `cleanup` from inside a worktree it is about to delete pulls the ground out from under the
   session. Nothing is lost: the artifacts dir was never in the worktree.
4. **Invoke `cleanup` in the orchestrator** — last step, so context cost is moot, and it may need to
   interact over `SESSION.md` triage. It finds no open PR on the current branch and says so, then does
   the work pim left it: deleting the merged branch and worktree, sweeping stale ones, draining
   `SESSION.md`.

Throughout the run, follow the repo's `SESSION.md` convention: incidental bugs and oddities the
orchestrator notices or subagents report get appended there instead of fixed inline.

## Reporting

Close with a short block, not a narrative:

- the merged PR number and the merge method chosen;
- the plan pass: findings fixed versus rejected, and anything it could not judge;
- the conformance pass: anything missing, extra, or misunderstood, and how it was resolved;
- code-review rounds, with **the stop rationale — what surface saturated**;
- CI green at merge, or that no checks exist;
- the tier profile, and any per-dispatch escalations;
- the artifacts dir path.

In degraded mode, say plainly what was skipped and where the changes now live.
