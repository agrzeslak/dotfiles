---
name: explain
description: Use when the operator writes `/explain` — they have lost the thread and want the last message you wrote put in plain English, along with however much of the surrounding context is needed for it to make sense. Explains what was said, why it came up, and where it leaves them; unpacks every term the message assumed they knew. Does no work, decides nothing, gates nothing. Operator-invoked only; `/explain <thing>` scopes it to that thing.
---

# Explain

## Overview

The operator has lost the thread. Somewhere in the last stretch — a wall of
tool calls, a term nobody defined, a plan that grew three levels deep — they
stopped following, and the last message you wrote landed on someone who could
no longer parse it.

**Put that message in plain English. Reach back exactly as far as it takes for
it to make sense. Hand control back.**

That is the whole job. You are not resuming the work, not re-planning, not
checking whether they now agree. You are getting them back into the driver's
seat, and then getting out of the way.

The two failure modes, both common:

1. **Re-saying it louder.** The same sentence with more words in it. If the
   explanation reuses the term that lost them, it has failed.
2. **Dumping the session.** A chronological recap of everything that happened.
   They did not ask where you have been; they asked what the last thing meant.

## Scope

- **Operator-invoked only.** Fires on `/explain`. Never offered unprompted,
  never self-triggered, never armed for later.
- **Trailing text scopes it.** Bare `/explain` targets the last message you
  wrote. `/explain the worktree thing` targets that instead — still explained
  with the same rules, still without doing anything about it.
- **Does no work.** No edits, no commands that change anything, no next step
  started "while I'm explaining anyway". Reading is fine and often necessary:
  open the file, the diff, or the plan when you need to ground a claim.
- **Gates nothing, decides nothing.** An explanation is not approval and not a
  re-plan. What happens next is theirs to say.
- **One pass, follow-ups welcome.** "Still lost" is a legitimate reply and it
  is handled below. The skill does not set a mode either way.

## Source of truth

**What you actually said and did, in this conversation.**

Explain the message that exists, not the message you wish you had written. If
the last message was vague, the explanation says what it was vague about. If a
step was skipped, the explanation says it was skipped. Quietly upgrading the
past into something tidier is the one thing that leaves them more lost than
they started, because now the chat and the explanation disagree.

If the conversation was compacted and the material is gone, explain what
survives and say in one line which part you no longer have.

## How far back to reach

Default to the **smallest reach that lands**. Pick it from why they are lost,
not from how much you could say:

| Lost because | Reach back to |
|---|---|
| The message used terms nobody introduced | The terms. Usually nothing further. |
| It is a step in a plan they lost the thread of | The goal, and where this step sits in it |
| It reports a result whose significance is unclear | What was expected, and what this changes |
| It asked them a decision they can't parse | The decision: the options and what each costs |
| Long tool-call stretch with no narration | What those calls were collectively for |
| They stepped away, or context was compacted | The spine only: goal, where we are, what's left |

One rule overrides the table: **if the thing that lost them sits further back,
go and get it.** A definition that depends on an earlier definition is not
optional. Reaching past that, into history that no longer bears on the current
message, is padding.

## Writing the explanation

- **Plain second person, active voice.** "You now have two branches" beats
  "two branches are now present".
- **Unpack every non-ordinary term at first use, in the sentence that uses
  it.** Not a glossary at the bottom.
- **Never define a term using its own family.** "A worktree is a linked
  checkout" explains nothing to someone who did not know worktree.
- **Concrete over general.** The actual file, the actual value, the actual way
  it breaks. Generality is what made the original message unreadable.
- **Short sentences.** One idea each. No stacked subordinate clauses.
- **At most one analogy**, only when the mechanism genuinely has a familiar
  shape, and always with the line where the analogy stops being true.
- **Do not soften.** If something is risky, unverified, or already broken,
  that is part of what they are missing. A reassuring explanation of a shaky
  situation is a lie with good manners.
- **No apology, no preamble.** Not "sorry that was dense" — just be clear.

### When the message was the problem

Sometimes they are lost because the message deserved to lose them: it
contradicted an earlier one, used a term two ways, asserted something you had
not actually checked, or wandered off what they asked for.

**Say so, plainly, in one line, in the explanation.** Then explain the real
situation underneath it. Do not reconstruct a coherent story that was never
there — that is how a drifted session stays drifted, with the operator now
confidently holding a version of events that never happened.

No self-flagellation. State it, correct it, move on.

## Output contract

Prose in the chat. Never a file, never a document, never an artifact.

Lead with **the point** — one or two sentences saying what the last message
actually meant. No run-up, no "let me walk you through this".

After that, only the parts that are earned:

- **Why it came up** — the chain back to their goal, at the depth chosen above.
- **The moving parts** — the terms and machinery the message assumed. Only the
  ones it actually used.
- **Where it leaves you** — the state of play now, and the pending decision if
  there is one. One or two lines. This part is almost always earned.

Hard limits:

- **About a screen.** An explanation that needs more than that has reached too
  far back. Cut the history, keep the meaning.
- **No questions to them**, with one exception: the last message asked them
  something that is still open, in which case restate it plainly as the closing
  line. That is the pending decision, not a new question of yours.
- **No offers, no next-step menu, no "want me to…?"** Handing control back is
  the ending.
- **Headings and bullets only when the content is genuinely a list.** Structure
  is not clarity; prose that reads straight through usually beats four labelled
  fragments.

If the last message was already plain and there is nothing to unpack, say that
in a line and name the one thing most likely to have been the sticking point.
Do not manufacture confusion to have something to explain.

## Follow-ups

"Still lost" means the explanation missed, not that it was too short.

**Re-explain smaller and from a different angle.** Go down a level of
abstraction, or start from the concrete thing on their screen and work
outwards. Do not repeat the same structure with more words, and do not reach
further back by default — the usual fix is reaching *less* far and being more
specific about the one piece that did not land.

If they name the part that lost them, explain only that part.

## Red flags — STOP, you are breaking the contract

| Urge | Do instead |
|---|---|
| Recap the session chronologically | Explain the last message. History only where it's load-bearing. |
| Use the term that lost them to explain itself | Define it in ordinary words, then use it. |
| Leave a term undefined because it is "standard" | Standard to you. Unpack it once, in line. |
| Re-say it with more words | Different angle, lower level, more concrete. |
| Tidy up what actually happened so it reads better | Explain what happened, including the mess. |
| Reassure them it's all fine | If it isn't, that's the part they're missing. |
| Start doing the work again "while I'm here" | Explanation only. Hand control back. |
| Re-plan or change the approach mid-explanation | Not this skill. They decide, afterwards. |
| Ask whether they now understand | Ends the pass. They'll say if they don't. |
| Close with "want me to continue?" | Say where it leaves them, then stop. |
| Reach back to the start of the session by default | Smallest reach that lands. |
| Write four headed sections for three sentences | Prose. Structure only when it's a list. |
| Emit it as a document or file | Chat prose. They're reading it right now. |
| Apologize for the original message | Just be clear. |
| Invent something to explain when nothing was unclear | One line saying so, plus the likely sticking point. |

## Example

````
/explain

The last message was saying: the change works, but I never proved it works
against the real database — only against a stand-in.

Why it came up: you asked for the migration to be safe to run twice. I wrote
the guard that makes the second run a no-op, and the tests I ran use an
in-memory database that fakes the table locks. So the tests passing tells you
the logic is right, and tells you nothing about whether the locking behaves the
same on Postgres.

The moving parts: "idempotent" just means running it twice does the same thing
as running it once — the second run finds the work already done and stops. The
guard is one `SELECT` that checks a marker row before doing anything. The gap
is that the fake database grants that `SELECT` a lock that Postgres would make
it wait for, so a second run arriving mid-flight is the case nothing has
exercised.

Where that leaves you: the code is written and the cheap tests pass. Whether
that is enough is your call — running it against a real Postgres instance would
close the gap, and it is the only thing left that I would call unverified.
````
