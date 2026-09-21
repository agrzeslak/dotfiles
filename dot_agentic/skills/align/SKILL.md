---
name: align
description: Use when the operator writes `/align` anywhere in a prompt — a one-shot alignment pass run before acting on that prompt. Ask the clarifying questions whose answers would change what gets built, push back on gaps the operator may not have spotted, and name non-obvious trade-offs they should at least be aware of before committing. Blocks exactly once, at the point of invocation, and is over as soon as the answers land. Domain-neutral — applies to any task, not just code. Not a mode, not a review, does not persist into the work that follows.
---

# Align

## Overview

The operator dropped `/align` into a prompt. They want the ask itself tightened
before you act on it.

**One pass — however many rounds it takes. Block. Hand control back.** Then the
skill is done, and the work that follows runs exactly as it would have without
`/align`, just on better inputs.

What you are hunting for, in priority order:

1. **Decisions that are theirs** — ambiguity where different readings produce
   materially different work.
2. **Gaps** — something the ask needs but never mentions, that they probably
   haven't noticed.
3. **Non-obvious trade-offs** — a consequence of what they asked for that they
   should know about *before* you commit to it.
4. **Wrong premise** — the stated approach won't reach the stated goal, or the
   goal behind the ask is better served another way (the XY problem).

## Scope — the whole point

`/align` is **bounded to its invocation point.**

- Blocks **there and only there**, before any work on that prompt.
- Runs **as many rounds as the ask genuinely needs** — an answer that reshapes
  the problem earns another round. See below.
- Does **not** re-arm. A fresh ambiguity 20 tool calls later is ordinary work:
  handle it the way you normally would.
- Does **not** persist. It sets no mode, no standing instruction, no "keep
  checking in" behavior for the rest of the session.
- Finding **nothing** is a legitimate outcome. Say so in one line and proceed.

Nobody invoking a lightweight tightening pass expects it to leak into the whole
pipeline. **Predictability is the feature.** Guard it.

### Rounds

One pass, many rounds. A round is warranted when the operator's own answers
**opened something new and material** — a decision that didn't exist before they
chose, a premise their answer exposed, a simplification their correction makes
possible. Their answers reshaping the problem is the pass working, not failing.

Each round faces a **higher bar than the last**. Round one asks what the prompt
left open. Round two asks only what round one's answers created. Round three had
better be load-bearing.

End the pass the moment any of these is true:

- The ask is tight enough to act on. **This is the normal ending** — not running
  out of questions.
- The operator says go, proceed, or just start. **Stop immediately**, even
  mid-thought, even with a question you liked. That's their call, and they have
  made it.
- A round would only polish: confirming what you already understand, checking
  your reading back, tidying wording. Do the work instead.

## Output contract

Two parts, in this order. Each is independently optional.

### 1. Concerns — short prose

Only for what is *not* a question for them to answer. One line each, no
paragraphs, roughly five lines maximum. Lead each with its kind:

- `Assumed:` — what you will take as given if they say nothing.
- `Gap:` — what the ask needs and doesn't mention.
- `Trade-off:` — a real cost of the chosen path, and what it buys.
- `Premise:` — where the approach and the goal may not line up.

State it and move on. No hedging, no build-up, no restating their request back
to them.

### 2. Questions — the AskUserQuestion tool

Only for decisions that are genuinely theirs.

- **Concrete options, never open prompts.** Not "what's the scope?" but two or
  three scopes they can pick between.
- **Every option's description carries its cost**, not just its meaning. The
  cost is the part they can't see and you can.
- **Recommend.** You usually have a view — put it first, label it
  `(Recommended)`. Withholding it is not neutrality, it's abdication.
- **Look before you ask.** Read the file, run the search, check the convention.
  Ask only what genuinely can't be answered that way.
- **Cap at 4.** More than four qualify? Ask the four that most change the work.

Then stop and wait. When the answers land, actually use them: either resume the
original task, or — if they opened something new and material — run one more
round under the rules above.

## What earns a question

| Earns one | Doesn't |
|---|---|
| Two readings → different deliverable | Two readings → same deliverable |
| A default they'd regret you picking silently | A conventional default exists |
| Cost they can't see (lock-in, blast radius, who maintains it) | Cost visible in the ask itself |
| Missing input the work structurally needs | Detail that can be filled in later |
| Approach won't reach the stated goal | Approach is merely not how you'd do it |

The bar: **would a careful colleague ask, or just get on with it?**

## When nobody can answer

Running as a subagent, in background, or in an unattended pipeline — blocking
cannot work, there is no one there. Do the pass anyway: print the concerns,
print the questions with the answers you're defaulting to, proceed.
**Never deadlock waiting on an absent operator.**

## Red flags — STOP, you are breaking the contract

| Urge | Do instead |
|---|---|
| Ask what you could learn by reading a file or running a search | Look first. Ask only what's left. |
| Keep "align mode" on for the rest of the session | One pass. It ended when the answers arrived. |
| Re-block later when something else gets murky | The pass ended. That's ordinary work now. |
| Open another round to confirm you understood, or to polish wording | Not material. Do the work. |
| Keep asking after they said "go" | Stop mid-thought. Their call, already made. |
| Treat one AskUserQuestion call as the whole quota | A reshaping answer earns another round. |
| Ask "shall I proceed?" / "is this ready?" | Not a decision of theirs. Proceed. |
| Emit eight questions to look thorough | Four, maximum. Fewer is usually better. |
| Ask bare open questions | Propose concrete options with their costs. |
| Withhold your recommendation to stay neutral | Recommend, and mark it. |
| Manufacture a concern because the skill "should" find one | One line saying it's clear, then proceed. |
| Expand into a full brainstorm or design session | Lightweight. Tighten the ask, hand back. |
| Start the work and ask afterwards | Block first. Afterwards is too late to be worth asking. |

## Example

````
Assumed: existing rows stay untouched; this applies to new writes only.
Gap: nothing says what happens to in-flight requests during the switchover.
Trade-off: the dual-write window makes rollback trivial but doubles write
  latency for its duration.

[AskUserQuestion]
  Q: How long does the dual-write window stay open?
    - One deploy cycle (Recommended) — rollback stays cheap, latency hit is
      hours not weeks. Cost: a second deploy to close it.
    - Until backfill completes — one deploy. Cost: latency hit lasts days, and
      the window is where the split-brain bugs live.
````
