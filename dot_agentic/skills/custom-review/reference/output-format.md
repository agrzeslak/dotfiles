# Output format

Read during the Review phase before drafting the final review. This file fixes the severity definitions, finding shape, ordering, coverage footer, skip list, and the zero-findings honesty rule.

The output rules are written as **hard prohibitions** where Codex's interview was emphatic. Treat them as gates, not suggestions.

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

## Finding shape

Every finding renders as:

```
**[Severity] path/to/file.ext:LINE — short headline**

When <condition>, this code does <wrong behavior> because <mechanism>, causing <impact>.

Fix direction: <one sentence>.

Related sites: file:LINE, file:LINE.   (omit this line if no related sites)
```

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

Codex's discipline: omit anything that does not help the author prevent a real defect or meaningful maintenance risk. Specifically:

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
- **Subagents used:**
  - Completeness audit — found 2 missing surfaces.
  - Sibling discovery — returned 4 candidates, 3 inspected.
  - Adversarial verification — 5 candidates submitted; 3 held, 1 narrowed, 1 dropped.
  - (omit subagents that didn't run)
- **Not checked:** <what was deliberately or unavoidably out of scope, with reason — e.g. `mobile/` excluded by operator focus directive; `vendor/` excluded as generated>.
- **Residual risk:** <items that could still go wrong that this review didn't close — typically low-confidence Low-severity observations, or known-unknowns>.
- **Test gaps:** <missing test coverage that matters for the change>.
```

If the Verification phase dropped candidates, optionally surface a count: *"5 candidate findings dropped at verification (see `tmp/custom-review-<ts>/verification.md` § Dropped candidates)."*

---

## Zero-findings rule

If after all phases no candidate survived verification, write the review explicitly:

```
# Custom Review — <target>

## Findings

No verified bugs found across this diff at the verification bar applied.

## Open questions
<list>

## Coverage
<full coverage section as above>

## Residual risk
<list>

## Test gaps
<list>
```

**Do not pad** with low-confidence suggestions to look productive. An honest empty review is a feature.

If after all phases you have **nothing** in findings, Open Questions, Residual Risk, AND Test Gaps — that itself is suspicious. Re-examine the Falsification phase: did you genuinely enumerate ≥3 falsifications per claim, or did you write "checked: no issue" too quickly? Re-do the Falsification phase for the claim with the broadest blast radius.

---

## Finding minimality discipline

If you have many verified findings after the Verification phase:

1. **Group by root cause** first. Five symptoms of one bug = one finding with five `related_sites`.
2. **Drop Low items** that don't materially help the author. Move them to Residual Risk.
3. **Be ruthless about Mediums.** Each Medium should carry a concrete failure path. Vague "edge case that might happen" → drop.
4. **Never dilute Criticals.** If you have one Critical and nine Lows, the Critical is what matters; the Lows can compete for residual-risk mention.

The optimization target is: *the author trusts that every reported item deserves attention.* Padding the review with marginal items destroys that trust.
