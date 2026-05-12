---
name: handoff
description: Compact the current conversation into a self-contained prompt that a fresh Claude Code session can paste in and execute. Use when the user wants to spawn a new agent/session to continue work — typically phrased "create a handoff for the agent that will be implementing X" or bare "/handoff". The skill emits a paste-able brief including the task statement, just enough placement context (cwd, key files, branch state, tooling, invariants), and pointers to skills the receiver should invoke. Ruthlessly filtered to X; not a general session summary.
---

# Handoff

## What this skill does

Compact this conversation into the minimum payload a **fresh Claude Code session in the same project** needs to start executing a specific task without rediscovery. Output is a single fenced block the user copies and pastes as the first message of the new session.

The receiver has filesystem and tool access but **zero conversation context**.

## Guiding heuristic

**Write everything you would want to know if you were the one doing the task — and nothing more.**

You (the current agent) just lived through the work. Imagine being handed only your draft brief and told to start on the task. Anything you would reach for, anything you would be annoyed not to know, anything you would re-derive from the conversation you no longer have — that belongs in the handoff. Anything else doesn't.

This catches things that fixed section templates miss:

- dead ends already tried ("we ruled out approach Z because Y")
- naming traps, look-alike files, two-plausible-mental-models situations
- library or API quirks discovered through trial
- subtle conventions the conversation established that no single file documents

It also keeps the brief honest: if the simulation produces nothing new for a section, drop the section.

## When to invoke

- Caller's prompt contains framing like *"create a handoff for the agent that will be implementing X"*, *"handoff for the next session"*, *"prepare a brief for a new chat doing Y"*.
- Bare `/handoff` — infer the most likely next task from conversation (and say so in the output so the user can correct).
- **Not** for end-of-chat summaries, status reports, or PM-style writeups. This is a launchpad for execution.

## Operating rules

- Single primary task. If multiple plausible tasks exist, pick one and (optionally) name a runner-up in one line.
- Ruthless filter: drop anything not relevant to the task. Unrelated detours from earlier in the conversation do not belong.
- Prefer **file:line references** over inlining code. Inline a snippet only when it was edited in conversation and has not been written to disk yet.
- Reference skills by name when the receiver should invoke them (e.g., `superpowers:test-driven-development`, `pentest-testing`). Do not paraphrase skill content.
- No motivational language, no architecture lectures, no roadmap recaps beyond what bears on the task.
- Hard cap: ~2000 tokens. Soft target: 300–1000 tokens. If over budget, drop inlined content to refs and trim "nice to know" sections first.

## Process

Run these steps before writing the handoff. Skip a step only when the conversation already provides the same information unambiguously.

1. **Establish the task (X).** Take it from the caller's prompt verbatim where possible. If absent, infer the highest-leverage next step from conversation and flag the inference at the top of the brief.
2. **Gather live placement state** with quick tool calls:
   - `pwd` — confirm working directory
   - `git rev-parse --show-toplevel && git branch --show-current` — repo root and branch
   - `git status --short` — what's dirty / staged
   - `git log --oneline -n 5` — recent commits (so the receiver doesn't redo them)
   - Conditionally: `ls` on a directory the task targets, if conversation didn't already describe its shape.
3. **Extract task-relevant context from the conversation:**
   - Files, symbols, tests, configs that the task will touch.
   - Decisions and invariants the user locked in that the receiver must preserve (these often live in side comments — surface them).
   - In-conversation edits not yet committed — these usually must be inlined.
   - Open questions the receiver needs to answer to proceed.
4. **Identify skills the receiver should invoke first.** Look at the task verb (implement, debug, test, scope, write finding, review). Name the load-bearing skill(s) in the output.
5. **Compose a draft.**
6. **Run the simulation pass.** Re-read the draft as if you've just been handed it and told to execute the task with no other context. For each thing you'd want to reach for that isn't there — a dead end, a gotcha, a related file, a convention, a "the real one is X not Y" — add it. For each bullet that you wouldn't actually use, cut it. Then re-check the length cap; drop inlined snippets to refs first if over budget.

## Output

Emit one fenced markdown block. The user copies it as the first message of the new session. Do **not** include preamble outside the block — anything outside is wasted.

Template:

````markdown
## Task
<One paragraph or 2–4 bullets describing exactly what the receiver should do. Take wording from the caller's prompt where possible. If inferred (bare /handoff), prefix with "(Inferred from prior conversation — correct if wrong.)">

## Placement
- **cwd**: `<absolute path>`
- **repo**: `<repo root>` on branch `<branch>`
- **dirty**: <list paths from `git status --short`, or "clean">
- **recent commits**: <2–4 entries from `git log --oneline`, only if they matter for the task>

## Files to know
- `path/to/file.rs:42-90` — <one-line role: "the function being modified", "where the trait is defined">
- `path/to/test.rs` — <relevance>
<Only files the receiver will need within the first few steps. Not exhaustive.>

## Constraints & invariants
- <Decision the receiver must preserve, with the reason in <=1 short clause if not obvious.>
- <Convention or contract that prior work depends on.>
<Skip section if there are none.>

## Skills to invoke first
- `<skill-name>` — <why>
<Skip section if none apply.>

## Open questions / decisions pending
- <Question the receiver needs to resolve, with the leading option if there is one.>
<Skip section if none.>

## Gotchas & dead ends
- <Approach already tried and ruled out, with the one-clause reason.>
- <Look-alike trap: "the real X is at path A, not path B; B is the old version".>
- <Library/API quirk discovered in this conversation that isn't in any doc.>
- <Convention this conversation established that no single file documents.>
<Skip section if the simulation pass surfaced nothing.>

## Uncommitted in-conversation edits
<Only when in-conversation changes haven't been written to disk. Inline minimal snippets with file paths. Skip section otherwise.>
````

## Style

- Terse. Strong nouns and verbs. Bullets over prose.
- One idea per bullet. Each bullet must earn its tokens.
- File paths exact. No "around line 40-ish".
- No hedging unless uncertainty is real and material to the task.
- Do not repeat the same fact in multiple sections.

## Quality bar

The simulation pass is the quality bar: re-read the draft as if you've just been handed it and told to execute the task with no other context.

- If there is anything you would reach for that isn't in the draft, add it.
- If there is anything in the draft you wouldn't actually use, cut it.
- If you'd be annoyed not to know something — a dead end, a naming trap, a quirk — it belongs in `Gotchas & dead ends`.

The draft is ready when the simulation produces no additions and no cuts.
