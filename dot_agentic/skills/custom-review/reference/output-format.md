# Output format

Read before workflow step 8 (write the rendered review). This file fixes the severity definitions, finding shape, ordering, coverage footer, skip list, and the zero-findings honesty rule.

The output rules are written as **hard prohibitions**. Treat them as gates, not suggestions.

---

## Severity bands

Use exactly four bands. Critical and High are also "blocking."

### Critical

Issues that can cause data loss, security bypass, privacy exposure, persistent corruption, irreversible user harm, or a deployment-breaking failure on a normal path.

> Example: a migration fails on existing rows with nulls. A server-side permission check was weakened.

Critical findings block merge.

### High

Real regressions in core workflows, common production paths, API compatibility, auth boundaries, payment/account behavior, or anything that makes the product materially wrong for users.

> Example: a refactored fetch loses its error branch and the UI renders "no results" on failure. An exported helper changed shape and three callers still expect the old shape.

High findings block merge.

### Medium

Confirmed bugs on less common but realistic paths: stale async results, missing error state, alternate mode broken, incorrect export, edit-path inconsistent with create-path, old data mishandled. Still findings, not polish.

Medium findings should be addressed but typically don't block merge.

### Low

Minor confirmed defects: misleading UI copy tied to state, recoverable bad behavior, narrowly scoped edge cases. **Include sparingly.** If higher-value findings exist, drop Low entries — or move them to the **Residual risk** list in the coverage footer.

---

## Severity rubric — procedural vs. semantic

Severity must reflect the kind of defect, not the kind of source it violates. A worked critique that motivates this rubric: *"the doc-table-stale finding is rated Medium primarily on the strength of AGENTS.md prose, which is more procedural than semantic. The `write_value` rollback bug — command Err but state mutated — is rated Low. That underweights a real 'command Err ⇒ silent state mutation' contract violation."*

**Ordering (highest impact first):**

1. **Observable-wrong-behavior** — the system says or does something materially false to a real user/caller. Floor **Medium**, ceiling **Critical**.
2. **Silent-state-divergence** — two layers can now disagree without an error surface (cache vs. truth, in-memory vs. on-disk, TUI mirror vs. engine). Floor **Medium**, ceiling **High**.
3. **Contract-violation-not-yet-visible** — code violates a documented contract (ADR, schema, doc bullet) but the violation hasn't surfaced. Floor **Low**, ceiling **Medium**. Promotes to bands 1/2 once a documented future consumer arrives.
4. **Procedural-doc-drift** — runtime-model tables, status lists, AGENTS.md prose, comment-precision items that lie about the code. Floor **Low**, ceiling **Medium**.
5. **Comment-precision** — adjacent docstrings/comments that mis-describe behavior in low-stakes ways. Floor **Low**, ceiling **Low**.

**Hard caps:**

- Doc-bullet contradicting impl with no observable user effect: **Low/Medium ceiling**.
- Command-Err-but-state-mutated, TUI optimistic flip without rollback, silent subscriber-cache divergence: **High/Medium floor**.
- Producer-without-wired-consumer ("dead feature shipped"): **High floor** if operator-visible (operator invokes the dead workflow believing it worked); otherwise Medium.
- Defensive flag with no observable read: **Low** — wasted code, not a bug. Promote to Medium only if the flag's appearance of working masks the read site needed for the actual fix.

**Producer-emits-lie-as-data (runtime-producer false content).** When a producer (engine code, command handler, dispatcher, persistence layer) writes false content into a persisted or operator-observable surface — audit log, `Query::*Detail` response, status line, persisted record, TUI mirror, metric, log key value — the defect is **observable-wrong-behavior**, Medium floor. This is a distinct class from `procedural-doc-drift`: the doc-vs-impl class is "the doc lies about code"; this class is "code emits a lie as data" that a real consumer reads at runtime.

Pre-existing producer code does not lower severity. Scope (whether the fix belongs in this PR) is separate from severity (how wrong the emitted value is). A pre-existing producer that is now amplified or made consumer-visible by this PR's changes remains Medium floor; deferral is a scope decision, not a calibration decision.

When in doubt between adjacent bands, ask: *what does the user / operator / next-developer see when the failure occurs?* The visible outcome decides the band.

The rubric is an internal calibration aid. The rendered finding does **not** need to label which band it belongs to — the severity prefix `[Critical|High|Medium|Low]` is the output; the band is the rationale.

---

## Finding shape

Every finding renders as:

```
**[Severity] path/to/file.ext:LINE — short headline**

When <condition>, this code does <wrong behavior> because <mechanism>, causing <impact>.

[Render proof: <one-sentence trace of the render path through suspend/restore/mount semantics, with file:line for each step. For prompt-command / keybinding / MCP-tool / CLI dispatch-failure findings, the dispatch chain (binding → emitter → engine receiver → handler) at file:line for each hop satisfies this.>.]
[Test proof: <test path:line — what the test asserts>.]

Fix direction: <one sentence>.

Related sites: file:LINE, file:LINE.   (omit this line if no related sites)
```

The `Render proof:` / `Test proof:` lines appear **only on visibility-dependent findings**. Other findings omit them. Their presence on a finding is what enforces the visibility-dependent finding-shape rule from `SKILL.md` — a visible-impact candidate without one of these proof lines is not a finding. The dispatch-chain carve-out (SKILL.md § *Visibility-dependent findings*) admits prompt-command / keybinding dispatch-failure findings using the dispatch chain as the render-path equivalent.

Required components — if any are absent, the finding is not yet a finding:

1. **Severity band** (Critical / High / Medium / Low).
2. **Primary site** as `path:LINE`. The exact line where the defect originates.
3. **Headline** — short, concrete, identifies *what* breaks. Not a bug category. `"Token refresh stores expired tokens"` not `"Cache invalidation bug"`.
4. **Condition** — the input, state, or timing under which the failure occurs.
5. **Behavior** — what the code actually does, in present tense, declarative voice.
6. **Mechanism** — why that wrong behavior happens, naming the specific code construct (missing guard, wrong predicate, race window, etc.).
7. **Impact** — what the user / data / system / caller observes. Concrete consequence, not "could lead to issues."
8. **Fix direction** — one sentence pointing at where to fix and how. **Not** a complete rewrite. Not a `diff`. The author still owns the fix.
9. **Related sites** (optional) — other file:line locations exhibiting the **same root cause**. Used to group same-cause findings into one entry.
10. **Render proof / Test proof** (only for visibility-dependent findings) — see above.

### Producer-claim finding shape

A finding about a producer whose value doesn't reach the consumer's actual read site must name producer / produced value / actual read site / actual source of truth at the read site / observable effect — all in the prose. Example:

> `src/editor.rs:120` writes `agent_permissions` to `config.toml`, but the command path at `src/engine.rs:211` constructs permissions from `AgentPermissionsConfig::default()` instead of reading that file. So `Ctrl+G` saves successfully while the engine continues using defaults.

No schema, no multi-field record. The sentence carries the structure.

### Claim-vs-reality finding shape

For findings whose defect is *"the codebase claims something false"* (comment overstates code; doc bullet contradicts impl; defensive flag with no observable read; stale runtime-model section), the impact statement should be explicit about the audience:

> `docs/runtime-model.md:42` says disconnected agents clear `permissions_filter`, but `src/session.rs:88` only clears it on project reset. The documented runtime model is false; maintainers extending this code will act on it. No user-visible bug today.

Severity for this class caps at Medium (see severity rubric). Promote to High only if a documented future consumer is in the same PR and the false claim will mislead them.

---

## Ordering

1. **By severity:** Critical → High → Medium → Low.
2. **Within severity, by root-cause group:** same-cause findings collapse to one entry with multiple `related_sites`. Don't list the same bug five times.
3. **Never by file.** A file-ordered review buries the most important findings.

Omit severity headings entirely when a band has zero findings (don't print `## Low (none)` — just don't print the heading).

---

## First-class finding classes

These deserve full finding-level treatment, not asides:

- **ADR / spec / doc deviations.** If the code contradicts a document the team has agreed on, that's a finding even if the code "works." The document is the contract.
- **Test contradictions.** A test that asserts the bug, or a fixture that hides the bug, is a finding (severity scaled to the underlying defect).
- **Deletion orphans.** Removed code with surviving consumers, docs, configs, flags, metrics, or tests — first-class finding.

---

## Hard prohibitions in finding text

These words and patterns are **forbidden** in any finding:

- **Hedging:** `maybe`, `possibly`, `seems like`, `might`, `could be`, `appears to`, `I think`, `probably`. Uncertain high-risk goes in **Open Questions**, not findings.
- **Confidence labels:** `[high confidence]`, `[unverified]`, `[needs check]`. A finding is either reported or it isn't.
- **Process narration:** *"I checked X"*, *"I searched for Y"*, *"After reading the file..."*. The Coverage section is where process goes.
- **Attribution:** *"the author forgot"*, *"this was missed"*, *"someone removed"*. Describe the code, not the person.
- **Praise or filler before findings:** no *"Overall this is well structured"* / *"The intent is clear"* lead-ins. Open with the first Critical finding.
- **Time spent:** *"After 30 minutes of analysis..."*. Never relevant.

---

## Skip list (do not include these as findings)

The discipline: omit anything that does not help the author prevent a real defect or meaningful maintenance risk. Specifically:

- **Pure style preferences** (indentation, brace style, line length, etc.) — handled by linters.
- **Naming nits** that don't cause misuse. (`userCount` vs `numUsers` does not cause bugs.)
- **"Consider X" without a concrete bug.** Either it's a bug → report as a finding; or it isn't → leave it out.
- **Generic architecture advice** (*"this would be cleaner as a hook"*, *"this could use the Repository pattern"*).
- **Restating what the diff already does.** The author wrote it; they know what it does.
- **Low-confidence guesses.** If you couldn't verify, drop it — or move to Open Questions if high-risk.
- **Unmotivated test requests** (*"add tests"* without naming which uncovered behavior matters).
- **Speculative rewrites.** Don't propose 200 lines of "alternative implementation."
- **"Feels risky"** without a concrete failure path. Vibes are not evidence.

A comment is beneath the bar if you cannot answer: *"What could break, for whom, under what condition?"* If the only answer is *"this could be cleaner,"* skip it.

---

## Open Questions section

This is the safety valve. **No hedging** does not mean false certainty. If you found a high-risk issue that you couldn't fully verify, put it here — not in findings, not in dropped, not nowhere.

Format:

```
## Open questions

- **path/to/file.ext:LINE** — <one-sentence statement of the uncertain risk>.
  What would resolve it: <what additional evidence / re-read / test would close the question>.
```

Only use Open Questions for items where the **uncertainty itself is the risk** — i.e. a Critical-or-High question that needs human-driven investigation. Routine Low ambiguities go into Residual Risk in the coverage footer.

---

## Coverage footer (always printed)

The coverage section is mandatory. It anchors the review's claims by stating what was inspected and what wasn't.

```
## Coverage

- **Files inspected:** <count> (<grouped by directory if long, e.g. `src/auth/ (5)`, `src/billing/ (3)`>)
- **Commands run:**
  - `git diff <base>...HEAD --stat`
  - `rg '<term1>|<term2>' --type ts`
  - `npm test -- src/auth/` (passed / failed: ...)
  - <every command actually executed>
- **Subagents used:** <if any spawned per SKILL.md *Subagents* triggers — name them and what they returned. Omit the bullet entirely if none ran.>
- **Falsifications:** N attempted across C claims; K promoted, M disproved, R residual / open. Break down per claim only when N ≥ 10 OR the review has zero promoted findings.
- **Not checked:** <what was deliberately or unavoidably out of scope, with reason — e.g. `mobile/` excluded by operator focus directive; `vendor/` excluded as generated>.
- **Residual risk:** <items that could still go wrong that this review didn't close — typically low-confidence Low-severity observations, or known-unknowns>.
- **Test gaps:** <missing test coverage that matters for the change>.
```

The **Falsifications** line is derived mechanically from `notes.md`: `N` counts all `falsifications:` bullets; `M` counts bullets tagged `disproved`; `K` counts `reachable-defect` bullets whose corresponding `Kn` ended `status=verified-finding-Fn`; `R` counts bullets tagged `open-question` plus `reachable-defect` bullets whose corresponding `Kn` ended `status=open-question-OQn` or was rendered only as Residual risk. The reviewer does not write these numbers from intuition.

---

## Zero-findings rule

If no candidate survived to a finding, write the review explicitly:

```
# Custom Review — <target>

## Findings

No verified bugs found across this diff at the verification bar applied.

## Open questions
<list, or omit the section if empty>

## Coverage
<full coverage section as above>
```

(Residual risk and Test gaps live inside the Coverage section; they are not separate top-level sections.)

**Do not pad** with low-confidence suggestions to look productive. An honest empty review is a feature.

If you have **nothing** in findings, Open Questions, Residual Risk, AND Test Gaps — that is suspicious. Return to workflow step 5 and run sideways search harder on the claim with the broadest blast radius.

---

## Finding minimality discipline

When many candidates survived:

1. **Group by root cause** first. Five symptoms of one bug = one finding with five `related_sites`.
2. **Drop Low items** that don't materially help the author. Move them to Residual Risk.
3. **Be ruthless about Mediums.** Each Medium should carry a concrete failure path. Vague "edge case that might happen" → drop.
4. **Never dilute Criticals.** If you have one Critical and nine Lows, the Critical is what matters; the Lows can compete for residual-risk mention.

The optimization target is: *the author trusts that every reported item deserves attention.* Padding the review with marginal items destroys that trust.
