---
name: handoff
description: create a terse, high-signal handoff at the end of a coding or implementation conversation. use when a step has just been completed and chatgpt should summarize what was achieved, why it mattered, and what the likely next best implementation step is so a fresh chat can continue without re-grounding from zero. trigger on requests about handoff, launchpad, what was just done, what to implement next, moving from step x to x+1, summarizing completed implementation work, or preparing a new coding chat with minimal context.
---

# Handoff

## Overview

Produce a compact handoff for the next coding model using only the context already present in the current conversation. Optimize for minimum re-grounding cost, not for completeness. Explain what was just accomplished, why it was done, and what the most likely next implementation step should be.

## Operating Rules

- Use only the current conversation context and any files or paths already mentioned in it.
- Do not ask the user for additional input if the conversation already contains enough signal to produce a useful handoff.
- Do not restate the full architecture or roadmap unless it is directly needed to justify the next step.
- Prefer concrete implementation context over abstract summaries.
- Prefer exact file paths, symbol names, interfaces, tests, and docs when they are available in context.
- Keep the output terse and dense.
- Do not include motivational language, project-management filler, or generic advice.
- Do not generate a prompt for the next chat unless explicitly asked. Output only the handoff text.
- If the context is incomplete or ambiguous, say so briefly and still provide the best grounded next step.

## Goal

Create an ultra high signal-noise launchpad for the next model so it can begin implementing the next step with minimal rediscovery.

## Reasoning Process

Follow this process internally before writing the handoff:

1. Identify the most recent concrete implementation outcome in the conversation.
2. Infer why that work was done from stated goals, constraints, roadmap notes, bug reports, or architectural decisions in the chat.
3. Extract the durable facts that matter for continuation:
   - completed behavior
   - touched components
   - decisions made
   - constraints or invariants
   - unresolved edges
4. Infer the most likely next best implementation step.
5. Prefer the next step that is:
   - directly unlocked by the completed work
   - small enough to start immediately
   - aligned with stated roadmap or architecture
   - constrained by the actual code and docs already referenced
6. Include pointers to source files or docs only when they are relevant to the next step.

## Selection Rules For The Next Step

Choose one primary next implementation step.

Prefer:
- the next dependent slice enabled by the completed work
- the highest-leverage unfinished piece already implied by the conversation
- the step with the clearest implementation boundary

Avoid:
- broad multi-epic plans
- speculative future work not grounded in the conversation
- testing, cleanup, or docs as the primary next step unless they are clearly the critical blocker
- listing many equal-priority options without making a recommendation

If multiple next steps are plausible, choose the best one and mention the runner-up in a short note only if it materially affects sequencing.

## Output Contract

Always use this exact structure:

### What just landed
Write 2-5 bullets describing the most recent completed implementation work. Be concrete.

### Why it matters
Write 1 short paragraph explaining the purpose of that work and how it changes the system or unlocks follow-on work.

### Next best implementation step
Write 1 short paragraph naming the single best next step and why it is next.

### Likely touch points
List the most relevant files, modules, classes, functions, tests, or docs already referenced in the conversation.
Use exact paths or names when available.

### Carry-forward constraints
List only the constraints, assumptions, or decisions that the next model must preserve.

### Open edges
List any unresolved details, risks, or ambiguities that could affect the next step.

## Style Requirements

- Be terse.
- Be specific.
- Use strong nouns and verbs.
- Prefer bullets over long prose.
- Keep each bullet to one idea.
- Avoid hedging unless uncertainty is real.
- Avoid repeating the same fact across sections.

## Quality Bar

A good handoff should let a fresh coding model answer: “What was completed, why was it done, and what should I implement next?” within a few seconds of reading.

If the conversation contains strong references to code or docs, include them.
If it does not, do not invent them.
