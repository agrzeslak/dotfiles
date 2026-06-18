---
name: progress
description: Use when the current chat already contains an implementation plan (multiple PRs, chunks, phases, or steps) and the user wants to see how far it has gotten — typically `/progress`, or "where are we", "what's left", "show progress", "what's the status of the plan". Emits a terse status checklist and nothing else.
---

# Progress

## Overview

The chat already holds a plan (multiple PRs / chunks / phases). Emit a terse
checklist of how far it has gotten — done, current, pending, blocked — grouped
by chunk, in execution order.

**Your entire response is the checklist.** No preamble, no summary prose, no
recommendation, no trailing question. The checklist *is* the answer.

## Source of truth

**This conversation.** The plan and what's been completed both come from what was
discussed here — not from scanning the repo. Take the chat at its word: if the
assistant said a PR merged, it's done.

Run a single targeted `git`/`gh`/file lookup **only** when the conversation itself
leaves a specific status genuinely unresolved (e.g. someone asked "did #430 actually
merge?" and it was never answered). Default is zero tool calls.

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
- **`[~]` and `[!]` items may carry a short parenthetical** reason. Nothing else
  gets prose. No other line explains, recommends, or asks.
- If the chat contains **no plan**, output exactly one line: `No plan in this conversation.`

## Example

````
search-indexing refactor — 1/4 chunks done

[x] PR 1: extract Indexer trait (merged #421)
[!] PR 2: SQLite FTS backend (deferred for PR 3)
    [x] schema + migration (merged #430)
    [x] implement trait
    [ ] feature-flag behind `sqlite-fts`
[~] PR 3: background reindex job
    [x] job runner
    [~] progress reporting
    [ ] cancellation
[!] PR 4: wire config switch (blocked on PR 2 + PR 3)
````

## Red flags — STOP, you are about to break the contract

| Urge | Do instead |
|------|------------|
| Explain that `/progress` isn't a known command | Just emit the checklist. |
| Add a "Where we are now" / "Summary" section | The `[~]` marker already says where we are. |
| Recommend what to do next | Not asked. Order implies it. |
| End with "Want me to…?" | Stop after the last checklist line. |
| Use `DONE` / `IN PROGRESS` text labels | Use the markers only. |
| Multiple `[~]` items | Pick the single active one; rest are `[ ]`/`[!]`. |
