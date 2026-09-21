---
name: quiz
description: Use when the operator writes `/quiz` — a Socratic check that they still understand what was done, or what is about to be done, and why. Asks one free-text question at a time about the decisions with consequences, never hands over the answer until they ask for it, and breaks off the moment a "wrong" answer turns out to be the better design. Operator-invoked only; not a mode, not a gate, not a summary.
---

# Quiz

## Overview

Working with an agent, the operator drifts. Approvals become reflex, the diff
stops getting read, and nobody is steering — least visibly to the operator
themselves. `/quiz` is the check.

**Ask them what was decided and why. One question at a time. Do not give them
the answer.**

The quiz has two possible payoffs, and the second is worth more than the first:

1. They can't answer → they have drifted, and the questioning walks them back
   to holding the decision themselves.
2. They answer "wrong" → and their wrong answer is better than what was
   decided. **Stop the quiz and go do that instead.**

## Scope

- **Operator-invoked only.** Fires on `/quiz`. Never self-triggered, never
  offered unprompted, never armed for later.
- **Never gates anything.** A quiz they fail blocks no merge, no
  implementation, no next step. It informs; they steer.
- **One pass.** It ends when they can steer again, or when they say stop. It
  sets no mode.
- **Not a summary.** If they wanted the state of play written out, that's
  `/progress` or a briefing. Handing over prose is the failure mode this skill
  exists to break.

## Source of truth

**This conversation, plus the plan or diff it points at.**

Take the chat's decisions at their word. Read a file, the diff, or a plan
document when you need to check an answer or ground a question — do not
repo-scan for new material to quiz on. If the conversation is compacted, quiz
what survives in context and say so in one line rather than inventing.

**Retrospective or prospective follows the chat's centre of gravity.** Work
already done → why it was done that way. Work planned and not started → why
that plan, and what it costs. Both present → the pending decisions first; they
are still reversible.

## What earns a question

Decisions with consequences. Not facts with answers.

| Earns one | Doesn't |
|---|---|
| Why X over Y, when Y was live | Which file the change landed in |
| What this costs, and what it buys | What a function is named |
| What breaks if the assumption is wrong | What a command does |
| What is still open, and who decides it | Anything they could answer by reading one line |
| What would make us reverse this | Anything with one obvious right answer |

The bar: **could they answer it correctly while still not steering?** Then it's
not a question, it's trivia. Cut it.

Mechanical recall is fair game only as scaffolding inside a why-question —
never as the question itself.

## The loop

1. **One question. Plain chat text. Then stop and wait.**
   Free text, not multiple choice: recognition lets a drifted operator pick the
   right option and stay drifted. Never batch questions; never number them
   ahead of time.

2. **Read the answer for the *why*, not the *what*.**
   Restating the decision is not understanding it. "We used a queue" is a
   what. "We used a queue because the writer can outrun the consumer during
   backfill and we'd rather buffer than drop" is a why.

3. **Vague, hedged, or wrong → narrow and re-ask.**
   Each retry is *smaller* than the last: offer a concrete fork, name the
   specific case, point at the consequence and ask what it implies. Never more
   than one narrowing question at a time.

4. **Do not give the answer. Ever — until they ask for it.**
   No cap on narrowing rounds. "Tell me", "I don't know, just say", "give it to
   me" — anything that reads as *release the answer* — is the only exit. Then
   state it plainly with its why, in a few lines, and move to the next question.
   No re-quizzing a spot they just asked you to hand over.

5. **Right answer → next question. No praise, no score.**
   "Yes" and move on. A tally turns this into a test to pass rather than a
   check on who is steering.

6. **End when they can steer**, when the consequential decisions are covered
   (usually three to five questions), or the instant they say stop. Close with
   at most one line. If nothing they missed matters, say nothing and stop.

## The divergence break

**The most valuable outcome, and it ends the quiz immediately.**

An answer that contradicts what was decided is a divergence — not an error —
when both hold:

- It is **coherent under a different premise**. They are not confused; they are
  working from a different assumption about the problem.
- It has a **real upside the decided path lacks**, or it exposes something
  nobody checked.

When both hold, **stop quizzing on the spot.** Do not finish the round, do not
bank it for the end, do not defend the decision because it is the one on
record. The design conversation is worth more than the remaining questions.

Break with exactly this, short:

- `Decided:` what the chat committed to, and on what premise.
- `You said:` their answer, in their terms.
- `Why yours may be better:` the upside, or the thing nobody checked.
- One question back to them — the call is theirs, not yours.

Then stop and hand control back. Do not adopt their answer, re-plan, or start
implementing off the back of the break. The quiz is over; what happens next is
ordinary work on their say-so.

**Wrong-and-worse is not divergence.** If their answer only works because they
have forgotten a constraint that was stated, that's step 3 — narrow and re-ask.

## Output contract

- One question per message. Nothing else in that message — no preamble, no
  recap of where we are, no "great question" framing of your own question.
- Questions are **short**. One or two sentences. A question needing a paragraph
  of setup is a briefing in disguise; cut it or split it.
- **No scores, no grades, no counts**, during or at the end.
- No recommendations, no next-step prose, no "want me to…?" — except the single
  question inside a divergence break.
- If the conversation holds **no consequential decisions** to quiz, output
  exactly one line: `Nothing consequential decided in this conversation to quiz on.`

## Example

````
Q: We put the retry budget on the client rather than the gateway. What does
that buy us, and what does it cost?

  > it retries so failed requests work

Q: Narrower — two services call this API. If the gateway held the budget
instead, what could it do that the client can't?

  > it'd see both of them, so it could stop retrying when everything's failing

Yes — one shared circuit, and it sheds load instead of amplifying it.

Q: We're spending the last chunk on a dual-write window before the cutover.
What is that window actually for?

  > rollback, right? but honestly why not just run the old reader against the
  > new store and leave writes alone until we trust it

Decided: dual-write for one deploy cycle, so rollback is a config flip.
You said: shadow-read the new store instead, cut writes over later.
Why yours may be better: it gets the same confidence without the write-latency
hit, and the split-brain bugs live in the dual-write window specifically —
shadow reads can't corrupt anything.

Does the rollback story still hold if writes never fork? That's the call I'd
want you to make before we build either one.
````

The quiz stops there. Two questions were still queued; they don't matter now.

## Red flags — STOP, you are about to break the contract

| Urge | Do instead |
|---|---|
| Summarize what's been done, then quiz on it | The summary *is* the drift. Ask cold. |
| Ask all the questions up front, or number them | One question, then wait. |
| Use AskUserQuestion / multiple choice | Free text. Recognition hides drift. |
| Give the answer because they're struggling | Only "tell me" releases it. No cap on narrowing. |
| Give the answer because the narrowing is taking too many rounds | Same rule. Their call, not your patience. |
| Say "correct!", tally a score, or end with "3/5" | "Yes", next question. No scores. |
| Bank a divergence and finish the round | Break immediately. That's the payoff. |
| Treat any wrong answer as divergence | Divergence needs a coherent premise *and* a real upside. |
| Defend the decided path when they diverge | State both, ask them, stop. |
| Start implementing their better idea off the break | Hand control back. Their say-so first. |
| Quiz which file changed, or what a flag is named | Trivia passes without steering. Ask why. |
| Block the work until they answer well | It never gates. It informs. |
| Offer `/quiz` unprompted, or arm it for later | Operator-invoked only. |
| Manufacture questions when nothing consequential was decided | One line saying so, then stop. |
