---
name: progress
description: Use when the current chat already contains an implementation plan (multiple PRs, chunks, phases, or steps) and the user wants to see how far it has gotten — typically `/progress`, or "where are we", "what's left", "show progress", "what's the status of the plan". Emits a terse status checklist.
---

# Progress

## Overview

The chat already holds a plan (multiple PRs / chunks / phases). Emit a terse
checklist of how far it has gotten — done, current, pending, blocked — grouped
by chunk, in execution order.

**Your response is the checklist, plus at most one trailing handoff offer (below).**
No preamble, no summary prose, no extra recommendations, no other trailing question.
The checklist *is* the answer.

## Source of truth

**This conversation, reconciled against what has actually merged.**

The plan and what's been completed both come from this chat — not from scanning the
repo. Take the chat at its word for the plan's shape and for any status it states.

But the chat may be **stale**: PRs land via CI, other sessions, or the user after the
chat last looked. So before emitting, run **one** bounded check for PRs that landed
since:

- `gh pr list --state merged --limit 30 --json number,title,mergedAt` (or the repo's
  equivalent), then cross-reference titles/numbers against the plan's chunks.
- If a chunk the chat thought pending/current has merged, mark it `[x]` and tag it
  `(landed #NNN)`. **This is the "bumped forward" reconciliation — the whole reason
  for the check.**

Bound it strictly: this one call only. Skip it silently if the plan references no PRs
or `gh` isn't available. Beyond this reconciliation, don't scan the repo to re-derive
status — at most one further targeted lookup, and only if the chat leaves a *specific*
status genuinely unresolved.

## Output contract

Markers, one item per line:

| Marker | Meaning |
|--------|---------|
| `[x]`  | done |
| `[~]`  | current — the one item being actively worked now |
| `[ ]`  | pending — not started |
| `[!]`  | blocked — waiting on a dependency or explicitly deferred |

Rules:

- **Group by PR / chunk.** Top-level item per chunk; nest sub-steps under it,
  indented 4 spaces. A chunk's own marker reflects its rollup (all sub-steps done →
  `[x]`; one sub-step active → `[~]`; etc.).
- **Execution order**, across and within groups. The order is the plan's order.
- **Exactly one `[~]`** — the true active focus. Everything else not-yet-started is
  `[ ]` or `[!]`, even if partially done with a paused sub-step.
- **Optional one-line header**: a terse summary if it adds context (plan name +
  count). Omit if it adds nothing. Never more than one line.
- **`[~]` and `[!]` items may carry a short parenthetical** reason; `[x]` items may
  carry `(merged #NNN)` / `(landed #NNN)`. Nothing else gets prose. No other line
  explains, recommends, or asks.
- **One trailing handoff offer** — the *only* line permitted after the checklist. If
  an actionable next chunk remains (earliest non-`[x]` chunk whose dependencies are all
  `[x]` — usually the `[~]`, or the first `[ ]` after it), append exactly one line:

  `Next: PR 3 — background reindex job. /handoff → /plan-implement-merge it?`

  Omit it entirely when the plan is fully `[x]` or every remaining chunk is `[!]`
  blocked on incomplete work. One chunk, one line, no rationale. If the user accepts,
  run `/handoff` scoped to that one chunk, then feed the brief to
  `/plan-implement-merge`.
- If the chat contains **no plan**, output exactly one line: `No plan in this conversation.`

## Example

````
search-indexing refactor — 2/4 chunks done

[x] PR 1: extract Indexer trait (merged #421)
[x] PR 2: SQLite FTS backend (landed #430)
    [x] schema + migration
    [x] implement trait
    [x] feature-flag behind `sqlite-fts`
[~] PR 3: background reindex job
    [ ] job runner
    [ ] progress reporting
    [ ] cancellation
[!] PR 4: wire config switch (blocked on PR 3)

Next: PR 3 — background reindex job. /handoff → /plan-implement-merge it?
````

PR 2 read as in-progress in the chat; the merged-PR check found #430 and bumped it to
`[x]`. If every remaining chunk were blocked or deferred, the final offer line is
omitted.

## Red flags — STOP, you are about to break the contract

| Urge | Do instead |
|------|------------|
| Explain that `/progress` isn't a known command | Just emit the checklist. |
| Add a "Where we are now" / "Summary" section | The `[~]` marker already says where we are. |
| Skip the merged-PR check to save a call | It's mandatory when the plan tracks PRs — stale `[x]` sets are the bug it fixes. |
| Recommend an approach or add next-step prose | The single handoff offer is the ONLY permitted recommendation. |
| Add a second trailing question, or a free-form "Want me to…?" | Exactly one scripted handoff offer, or none. |
| Justify *why* the next chunk is next, inside the offer | Offer is one line: chunk + the handoff question. No rationale. |
| Use `DONE` / `IN PROGRESS` text labels | Use the markers only. |
| Multiple `[~]` items | Pick the single active one; rest are `[ ]`/`[!]`. |
