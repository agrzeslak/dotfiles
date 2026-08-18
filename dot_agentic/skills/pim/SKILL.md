---
name: pim
description: Lightweight plan → implement → merge pipeline. Takes a feature description, a pointer to where one lives, or a ready-made plan. Without a plan it questions the operator until the ask is understood (especially the non-obvious trade-offs), writes a plan, and hardens it with one repo-grounded review pass; with a plan it goes straight to implementation. Then it loops `/custom-review` — orchestrator triaging which findings are worth fixing — verifies locally, opens a PR, waits for CI to go green, merges with the repo's own convention, and cleans up. Every plan, review, implementation, and fix runs in a subagent whose model tier the orchestrator picks. Use when the operator invokes `/pim <description | path | plan>`.
---

# pim — plan → implement → merge

Ship one change end to end: plan, harden the plan, implement, harden the code, merge. The small
sibling of `plan-implement-merge` — one reviewer instead of three, orchestrator-triaged fixes
instead of apply-everything, no reviewer-comparison bookkeeping. Escalate to that skill when the
change wants a second instrument on the same code: codex's outside model, or `code-review`'s finder
fan-out, which catches removed-guard regressions `custom-review` reads past. pim accepts one
reviewer's blind spots by design and never bolts a second reviewer on.

## Orchestrator

The agent running this skill orchestrates and never plans, reviews, or writes code itself. Plan text,
diffs, and review output live in subagents so the orchestrator's judgment stays uncrowded.

**Durable state** — write it to `<artifacts dir>/ledger.md` as you go, so an interrupted run is
resumable:

- **target** and **mode** (`plan-supplied` or `plan-from-description`);
- **tier profile**;
- **artifacts dir** — `<origin repo root>/tmp/pim/<run-slug>/`, resolved *before* entering the
  worktree so artifacts outlive it;
- **worktree path**, **feature branch**, **base branch**;
- **plan path** — `<artifacts dir>/plan.md`, unless the repo tracks plan documents (Step 2);
- **PR number**;
- **round ledger** — one line for the plan pass and one per code-review round: surface reviewed,
  findings raised, which were fixed, which were rejected and why, gaps opened.

**Jobs:** talk to the operator (subagents cannot ask), pick tiers, dispatch rounds, triage findings,
apply the stop rule, own every push. Context-free git and `gh` calls may run inline.

**Push invariant.** A push fires CI, so exactly two actions push: opening the PR (Step 6) and
re-pushing a CI fix (Step 7). Every subagent commits and never pushes.

## Argument

Trailing text after `/pim` is the target; empty → refuse, asking for a description, path, or plan. A
path that resolves is read and classified, and **the verdict printed in one line** before work starts
— `Target: docs/spec-foo.md — a spec; planning from it.` Misclassification is cheap to catch here,
expensive later, and the operator is the only one who can catch it.

- **Plan** — ordered tasks with concrete file paths and acceptance criteria → mode `plan-supplied`;
  skip Steps 1–3. A supplied plan is assumed already hardened, typically by an earlier pim run.
- **Spec** — prose stating what is wanted, no task decomposition → mode `plan-from-description`.
- **A directory** → a spec reference for the planner to read. **Anything that does not resolve** → an
  inline description. Both are `plan-from-description`.

## Tier profile (print it)

Three roles take a model: **planner**, **reviewer**, and **implementer/fixer** — *fixer* being whoever
applies a finding the orchestrator selected, to the plan (Step 3), the code (Step 5), or a red build
(Step 7). Fixers sit with implementers because the thinking is already done: the reviewer proved the
defect and named its consequence, the orchestrator ruled it worth fixing, and a bounded edit is what
remains.

| Profile | When | Planner / reviewer | Implementer / fixer |
|---|---|---|---|
| `standard` | the default | `opus` | `sonnet` |
| `hard` | real ambiguity remains, the change is intricate, or it is security- or data-integrity-sensitive | `opus` | `opus` |
| `trivial` | small, mechanical, low-stakes — a rename, a doc edit, a config tweak, one file with obvious semantics | `sonnet` | `sonnet` |

Skim the target and the code it touches, assign one profile, and **print it with its reason** so the
operator can interrupt. Pass the tier as each `Agent` dispatch's `model`. Re-assess once against the
plan — supplied or written — since a plan thornier than its description moves `standard` → `hard`; say
so in one line.

**Per-dispatch escalation.** A single fix dispatch may run at `opus` while the profile stays put, for
one of these reasons and no others, because "when in doubt" quietly becomes always-`opus`:

- the fix is **not localized** — it spans layers, modules, or call sites that must stay consistent;
- the reviewer proved the **defect but not a safe remedy**, so fixing needs a design decision;
- the surface is **security-, data-integrity-, concurrency-, or migration**-sensitive;
- the single plan-fix dispatch faces a finding demanding a **restructure** rather than a correction.

Escalate the dispatch, not the profile, and print the reason.

## Preconditions and degraded modes

**Refuse only on a missing skill:** `custom-review` (pim's only reviewer — nothing covers for it),
`superpowers:writing-plans`, `cleanup`. Missing `superpowers:test-driven-development` or
`superpowers:subagent-driven-development` degrades to one implementer subagent testing by the policy
below.

Everything else degrades, and **which capability is lost depends on which piece is missing** — probe
all three, then print one line naming the case:

| Missing | Still runs | Skipped |
|---|---|---|
| Not a git repo (`git rev-parse --git-dir`) | plan, implement, review via custom-review's `paths` target over the changed files | worktree, branch, commits, PR, CI, merge, cleanup |
| Git repo, no remote (`git remote`) | worktree off the local default branch, commits, review `against <base>` | PR, CI, merge |
| `gh` missing or unauthenticated (`command -v gh`; `gh auth status` to a file) | everything local, including the push | PR, CI, merge |

Example: `Skipped PR/CI/merge/cleanup: not a git repository; changes are in the working tree.`
Skill-authoring directories and scratch trees are not repos — this path is real, not hypothetical.

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

**Resolve the base branch yourself rather than inferring it from the tool.** `EnterWorktree` branches
from `origin/<default branch>` under the default `worktree.baseRef: fresh`, but a `head` setting
branches from local HEAD instead — and a wrong base silently mis-scopes every review and the PR. Take
the base from `git symbolic-ref --short refs/remotes/origin/HEAD` (strip `origin/`; fall back to
`main`), then confirm with `git merge-base --is-ancestor <base> HEAD`. If that fails, the real base is
what `git merge-base` reports against the branch you actually started from.

## Stop rule — diminishing returns (Step 5)

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
mismatches between layers, anything that makes the code or UI state a falsehood, and misses against
the plan's acceptance criteria. **Reject** preference, phrasing, taste, speculative future-proofing,
and any finding whose cited evidence does not hold up. Record every rejection with its reason in
`<artifacts dir>/ledger.md` — an unrecorded rejection gets re-litigated every round. Real findings
that are out of this change's scope go to `SESSION.md` per the repo convention, not into the loop.

## Two strikes on any fix-and-retry loop

Three loops retry a fix against the same failing signal: acceptance criteria (Step 4), the repo's own
checks (Step 6), and red CI (Step 7). Each stops after the **second** failed attempt on the same failure
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
> regression, a flaky test. Watch it fail *for the right reason*, implement, watch it pass; follow
> `superpowers:test-driven-development`. **Skip the test** — do not manufacture ceremony — for a pure
> rename, a comment or docs edit, formatting or lint, dead-code removal, a type-only change with no
> runtime effect, a config or build change with no unit-testable surface, or a finding an existing
> failing test already covers (name it). Note in the commit message why no test was added.

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
hedging. If the ask is shapeless, invoke `superpowers:brainstorming` first, then question the forks it
surfaces.

Write the locked intent to `<artifacts dir>/intent.md` — goal, approach, scope, acceptance criteria,
constraints, edge cases, and every assumption made under an opt-out. The planner reads that, not the
dialogue.

## Step 2 — Plan (subagent, planner tier)

Dispatch one subagent to invoke `superpowers:writing-plans` against the target plus
`<artifacts dir>/intent.md`. Tell it no human is reachable: on a genuine ambiguity, make the most
reasonable call and record it in the plan rather than stalling. It reports the plan path — the skill
writes to `docs/superpowers/plans/YYYY-MM-DD-<feature>.md` — and a one-paragraph summary.

**Suppress that skill's execution handoff.** `writing-plans` ends by asking the operator to choose
between subagent-driven and inline execution. Nobody can answer inside a subagent, and pim owns that
choice (Step 4). Tell the planner to stop once the plan is written and reviewed, and to report the path
instead of offering options.

**The plan does not get committed.** It is scaffolding for this run — the same reason the comment
hygiene block keeps run labels out of the code — and a merged plan goes stale immediately, then
misleads whoever finds it. So **move** it out of the worktree into `<artifacts dir>/plan.md` (do not
copy: an untracked file left in `docs/superpowers/plans/` would either dirty the tree Step 5 needs
clean, or get swept into a commit by an implementer) and pass that path onward. Everything downstream
reads the plan from the artifacts dir.

The exception is a repo that **already tracks plan documents** — existing committed plans under
`docs/plans/`, `docs/superpowers/plans/`, or similar. Then follow the repo's convention over pim's:
leave the plan in place and let it be committed, exactly as with the merge method in Step 8.

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
  implementers record the assumptions they had to make, Step 4 verifies the acceptance criteria, and
  Step 5's reviewer reads the plan as claims about the branch.

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

Pick the shape and say which:

- **one implementer subagent** when the plan is small or its tasks are tightly coupled;
- **per-task fan-out** when the plan has independent tasks — a fresh subagent per task. **The
  orchestrator runs `superpowers:subagent-driven-development`'s dispatch loop itself**, since
  dispatching is its job; it keeps only compact per-task summaries.

Every implementation subagent gets the plan path, the task(s) it owns, the **TDD policy** and **comment
hygiene** blocks verbatim, and: commit with semantic messages, never push.

**Run that skill for its dispatch loop only, and skip every review stage it defines** — the per-task
spec-compliance reviewer, the per-task code-quality reviewer, the final whole-implementation reviewer,
and the terminal handoff to `superpowers:finishing-a-development-branch`. Review lives in Step 5, pim
owns Steps 6–8, and on a six-task plan those stages are a dozen-plus dispatches each reading a slice of
a diff Step 5 reads whole. Two consequences, both accepted: a task built wrong surfaces at Step 5 rather
than at task N, so later tasks may build on it; and the **quality axis** — reuse, simplification, dead
abstraction — goes uncovered, since `custom-review` promotes only proof-gated correctness findings. Run
`/simplify` afterwards if that starts to bite.

Then dispatch a **verification subagent** to check the plan's acceptance criteria one by one, each
reported met or not with the command or observation that shows it. Fix misses with a fix subagent (same
tier rules, same two blocks) and re-verify, under the two-strikes rule — a criterion that fails twice
usually means the plan is wrong about the codebase. Otherwise leave the tree clean and everything
committed; Step 5 reviews committed state.

## Step 5 — Code review loop

A review dispatch per round, plus a fix dispatch when the orchestrator selects findings. Stop per the
stop rule.

**Round N reviewer** (reviewer tier):

```
Round N — code review of branch <feature branch> against <base>
Plan: <plan path> — outside the diff by default, so custom-review will not discover it on its own.
Pass its path to the skill and read it as claims about the code shipping against it: an obligation
the plan states and the branch does not meet is a finding, not merely a coverage note.
Gap this round covers: <named gap; for round 1, the full diff>
Already examined: <ledger's one-line entries; empty for round 1>

Invoke the `custom-review` skill via the Skill tool with the target `against <base>`. In degraded
mode (no git repo) pass the changed file paths instead — that selects custom-review's `paths`
target. When a gap is named above, append it verbatim as trailing focus text; the skill reads that
as an `Additional focus:` directive.

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
- **Focus biases; it does not narrow.** A named gap steers falsification toward that question, but the
  broad pass reruns every round. So round 1's Coverage footer is the inventory later rounds are
  measured against, previously-read surface gets re-covered for free, a gap round costs about what
  round 1 cost, and the bar for another round is higher here than for a reviewer that can be scoped
  down. Expect fewer rounds than `plan-implement-merge` takes.

Findings arrive proof-gated — condition, wrong behavior, and impact at `file:line`, each link re-read —
so triage is mostly *fix now versus defer to `SESSION.md`* rather than *believe or reject*. A finding
whose evidence still does not hold on inspection is a rejection worth recording, since it also says
something about `custom-review` itself.

The **fix subagent** (implementer/fixer tier, escalated per dispatch when a named reason applies) gets
the selected findings verbatim, the **TDD policy** and **comment hygiene** blocks, and: commit each fix
with a semantic message, leave nothing uncommitted, **do not push**, do not re-review your own fixes.
It reports what it changed and whether that is broad enough to count as new surface.

**A refused review is a failed round.** `custom-review` refuses on an empty diff, and on a PR target
whose local branch is ahead or diverged. Neither should happen here — Step 4 leaves everything
committed and this loop reviews a local branch — but if one does, fix the cause and re-dispatch the
same gap rather than reading the refusal as convergence.

## Step 6 — Verify locally, then open the PR

Once the loop converges, dispatch one subagent to detect and run the repo's own checks — tests, lint,
type-check, build, whatever it actually defines (`Makefile`, `justfile`, `package.json` scripts,
`cargo test`, CI config) — reporting each as pass or fail with the failing output, and pushing nothing.
Fix failures with a fix subagent and re-run, under the two-strikes rule. If the repo defines no checks,
say so in one line and continue. This runs once per run rather than per round: it catches most red-CI
cases at zero CI cost without putting a full test run on every review round.

Then the **orchestrator pushes** — the run's first push, on code that has already cleared review — and
dispatches a subagent to open the PR: read the branch's commits and run `gh pr create` against
`<base>` with a semantic title, a wrapped body explaining the non-obvious trade-offs, a test-plan
checklist, and the Claude Code attribution footer. Capture the PR number.

## Step 7 — CI gate

The PR does not merge on a red build, and a converged review is not a passing build.

1. **Watch** (orchestrator, background, generous timeout): `gh pr checks <num> --watch --interval 30`,
   output to a file. Exit 0 means every check passed.
2. **No checks reported** → print `CI gate skipped: no checks reported for <sha>` and go to Step 8.
   Never block on checks that will never appear.
3. **Any failure** → dispatch a fix subagent (implementer/fixer tier; a cause that is not localized or
   not legible from the log is a named escalation reason): read the failing logs — `gh pr checks
   <num>`, `gh run view <run-id> --log-failed`, each captured to a file — reproduce locally, fix the
   root cause under the TDD policy, commit, do not push. It classifies its own fix as *trivial* (lint,
   format, flake, config, infra — no behavior change) or *substantive*, defaulting to substantive.
4. A **substantive** fix is new surface: run one Step 5 round with that fix as its named focus before
   pushing, so the two gates never fall out of sync. Trivial fixes skip this.
5. The orchestrator pushes and returns to 1, under the two-strikes rule — a check that fails twice on
   the same cause goes to the operator rather than into a third push.

## Step 8 — Merge, leave the worktree, clean up

**pim decides *when* to merge; `cleanup` owns *how*.** That skill's Step 1 already merges the PR,
already picks the method from what the repo allows (preferring squash), and already composes the squash
subject and body from the PR title and body so GitHub does not concatenate every branch commit subject.
Do not restate that algorithm here — a second copy would drift, and pim's copy would be the worse one.

pim still issues the merge itself, for a worktree reason: `cleanup` finds the PR from the *current*
branch, and it refuses to delete the branch or worktree it is running in. So:

1. **Merge** with `gh pr merge <num>`, using `cleanup`'s Step 1 rule for the method — prefer squash,
   fall back to whatever the repo permits, compose the squash subject and body explicitly. Print which
   method and why. Leave branch deletion to `cleanup`, so one step owns it.
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
- code-review rounds, with **the stop rationale — what surface saturated**;
- CI green at merge, or that no checks exist;
- the tier profile, and any per-dispatch escalations;
- the artifacts dir path.

In degraded mode, say plainly what was skipped and where the changes now live.
