# Artifact schema

The skill writes seven artifacts under `tmp/custom-review-<ts>/`, one per phase. Each artifact uses **structured bullets** with stable IDs and required fields keyed `field=value`. Tables fail on code-context reasoning; freeform prose fails on accountability. Structured bullets are the right middle.

Each record has:
- A stable ID prefixed by a one- or two-letter type marker (`[S0]`, `[Src1]`, `[C1]`, `[Sf1]`, `[T1]`, `[H17]`, `[A1]`, `[Sb1]`, `[Fa1]`, `[Ta1]`, `[F1]`, `[D1]`).
- Required fields keyed `field=value`. Values inline; long notes go on indented lines below.
- A lifecycle status where applicable.

IDs are unique within their artifact file and stable across rewrites — if a record is revised, keep the ID and mark `revised=true`.

## Forbidden marker values (structured fields only)

A phase's gate fails when these tokens appear as **values of a structured field**:

`todo`, `tbd`, `fixme`, `unclassified`, `unread`, `assumed`, `needs-read`, `verify` (meaning "not yet verified"), `inconclusive` (outside the transient falsification → verification window in `falsification.md`).

The rule is **value-only**. These tokens may legitimately appear as substrings of code identifiers, file paths, grep output, quoted comments, or natural-language notes (`verifyToken`, `unreadCount`, a copied `// TODO: refactor`). The matcher is "is this a structured field value declaring incomplete state?" — not "does this token appear anywhere?"

The only acceptable form of "I couldn't do this" is a written reason: `N/A reason=...`, `gap=...`, `skipped=true reason=...`. `inconclusive` is permitted only inside `falsification.md` and only until the Verification phase ends.

## Discipline: concise artifacts

Artifacts prove the search closed. They are not the review and they are not a transcript.

- Do not paste full grep output. Cite line counts and representative lines.
- Do not duplicate the diff. Cite file:line.
- A surface with no hits gets one line, not a paragraph.
- Notes under a bullet should be reasoning ("this caller is safe because X"), not narration ("I read this file and then I read that file").

---

## `scope.md` — Scope phase

One record only.

```
[S0] target=<pr|branch|commit|uncommitted|paths|snippet>
     identifier=<PR#|sha|branch-name|HEAD|path-list|"pasted">
     base=<base ref or N/A>
     focus=<focus text or none>
     changed_files=<count or N/A>
     additions=<count or N/A>
     deletions=<count or N/A>
     dirty_worktree=<yes|no|N/A>
     untracked_files=<count or N/A>
     review_started=<ISO-8601 UTC>
```

For diff-based targets: save raw `git diff` to `$DIR/diff.patch` alongside `scope.md`. For `snippet`: save pasted code to `$DIR/inputs/`.

---

## `model.md` — Model phase

Three sections in order: `## Sources`, `## Claims`, `## Surfaces`.

### Sources

One record per consulted source.

```
[Src1] path=<file or external URL> kind=<claude-md|agents-md|gemini-md|contributing|adr|spec|schema|pr-body|migration|conflict> touched=<yes|no> relevance=<high|medium|low>
       summary=<one-line normative claim this source asserts>
       potential_drift=<ADR-id> (omit if no apparent drift)
```

For `kind=conflict`: `summary` names the conflicting sources and the resolution (`unresolved` is permitted; an unresolved conflict becomes a candidate finding in the Falsification phase).

### Claims

One record per falsifiable claim.

```
[C1] surface=<short name> kind=<behavior|contract|invariant|refactor-claim|deletion-claim>
     promise=The code now promises that <X>.
     falsified_if=X is false if <Y>.
     authority=<Src1,Src2,...>
```

For `paths`/`snippet` targets, `promise` drops the "now": `The code promises that <X>.`

### Surfaces

One record per semantic surface.

```
[Sf1] kind=<field|type|enum|status|route|endpoint|query-key|cache-key|event|job|flag|config|permission|column|serialized|exported|env|error-code|log-key|metric|deletion|none>
      change=<added|removed|renamed|reshape|behavior-only>
      old_form=<name/value before, or `N/A` if change=added>
      new_form=<name/value after, or `N/A` if change=removed>
      grep_terms=<comma-separated search strings driving Search phase, or `none` if un-greppable>
      file_origin=<file:line>
      claim_refs=<C1,C3>
```

`grep_terms` is the authoritative search list. `old_form`/`new_form` are descriptive labels, never used as literal searches. `N/A` is never a search term. For un-greppable surfaces (behavioral invariants without a symbolic name), `grep_terms=none` and the closure plan goes in a note below the bullet.

---

## `search.md` — Search phase

Four sections in order: `## Traces`, `## Hits`, `## Completeness audit`, `## Siblings`.

### Traces

One block per claim.

```
[T1] claim=C1
     producer=path:line — <what emits the value/event/state>
     transform=path:line — <serialization, validation, transformation>
     storage=path:line — <persistence, cache, in-memory state>
     transport=path:line — <API/IPC/queue boundary>
     consumer=path:line — <what reads the value>
     effect=path:line — <user/operator/caller observable>
     gaps=<segments not found in code; do not invent>
```

UI claims: replace `transport` with `state`, `effect` with `render`. Data claims (migrations, ETL): replace `effect` with `downstream-consumer`.

### Hits

One bullet per hit (or per batch).

```
[H1] surface=Sf1 path=src/auth.ts:142 role=<producer|consumer|transformer|serializer|storage|migration|validation|permission|cache|ui-render|test|doc|generated|irrelevant> status=<read-ok|read-suspect|batched|irrelevant>
     note=<one sentence — what this consumer does with the surface>
```

For batches:

```
[H8] surface=Sf3 kind=batch count=42 pattern=<regex or natural description> role=<role> status=batched
     rationale=<why batching is safe — what's mechanically identical>
     representative=path:line
     outliers=path:line, path:line
```

### Completeness audit

If the audit subagent ran:

```
[A1] missing_surface=<bullet from subagent, verbatim>
     disposition=<added-to-surfaces|rejected> reason=<why>
```

If `surfaces` in `model.md` was confirmed complete:

```
[A0] result=complete reason=subagent found no missing surfaces.
```

If the audit was skipped (per trigger conditions):

```
[A0] skipped=true reason=tiny-local-pr-no-contract-boundary
```

### Siblings

One block per claim.

```
[Sb1] claim=C1
      axes_checked:
        - create_vs_edit: <inspected-both|only-<side>|N/A reason=...>
        - single_vs_bulk: ...
        - admin_vs_user: ...
        - mobile_vs_desktop: ...
        - success_vs_error: ...
        - success_vs_loading: ...
        - success_vs_empty: ...
        - initial_vs_retry: ...
        - initial_vs_cancel: ...
        - deletion_mirror: ...
      candidate_siblings:
        - path=src/x.ts kind=create-counterpart status=read-suspect note=...
        - path=src/y.ts kind=bulk-counterpart status=read-ok note=...
```

`N/A` requires a reason. *"Not applicable"* without justification is forbidden.

---

## `falsification.md` — Falsification phase (and append target for Tests phase)

This file is the **unified candidate-findings store**. Three record `kind`s:

- `kind=falsification` — per-claim attempts (the bulk), written during the Falsification phase. One block per claim.
- `kind=source-conflict` — written during the Falsification phase from `model.md` records flagged `unresolved` or with `potential_drift`. One block per conflict.
- `kind=test-derived` — appended during the Tests phase from coverage gaps over `reachable-defect`s or from fixture-blindness defects. One block per gap.

The Verification phase iterates over **all** records in this file, regardless of `kind`.

### kind=falsification

```
[Fa1] kind=falsification claim=C1
      falsifications:
        - id=Fa1.1 hypothesis=<what would make the claim false> verification_path=<files/lines read> result=<disproved|reachable-defect|inconclusive> notes=...
        - id=Fa1.2 ...
        - id=Fa1.3 ...
      backward_compat: <findings or "checked: no issue">
      failure_parity: <findings or "checked: no issue">
      async_invalidation: <findings or "N/A reason=no async surface">
      deletion_orphans: <findings or "N/A reason=no deletion">
```

### kind=source-conflict

```
[Fa7] kind=source-conflict source_refs=Src3,Src5
      authority_chosen=<Src3 | unresolved>
      hypothesis=<the resolution implied by the chosen authority is correct>
      verification_path=<files/lines that test the resolution>
      result=<disproved | reachable-defect | inconclusive>
      notes=<why this conflict is a candidate finding — typically: code now contradicts an ADR; or two sources cannot both be true>
```

### kind=test-derived

```
[Fa9] kind=test-derived underlying_fa=Fa3.2 (omit if not derived from an existing Fa)
      test_site=tests/auth.test.ts:142
      hypothesis=<the defect the test should have caught but doesn't, or the defect implied by a fixture-blind assertion>
      verification_path=<files/lines that prove the gap matters>
      result=<reachable-defect | inconclusive>
      notes=<why the existing test does not close this — fixture blindness, wrong assertion, missing case>
```

`result=inconclusive` is permitted transiently and must resolve to `reachable-defect` or `disproved` before the Verification phase closes — for any `kind`.

---

## `tests.md` — Tests phase

One block per touched test file.

```
[Ta1] path=tests/auth.test.ts
      fixture_blindness:
        - <what does the fixture make impossible to fail?>
        - <what coverage does the fixture not include?>
      assertion_audit:
        - <does the assertion encode the regression? does it assert the wrong thing?>
      coverage_gaps:
        - <Fa-IDs from falsification.md not covered by this test>
      new_tests_added: <yes|no|missing-but-recommended>
```

---

## `verification.md` — Verification phase

Two sections: `## Verified findings` (`[F1]` records) and `## Dropped candidates` (`[D1]` records).

### Verified findings

```
[F1] severity=<Critical|High|Medium|Low>
     headline=<short, concrete; not a category>
     primary_site=path:line
     condition=When <input/state/timing>, ...
     behavior=...this code does <wrong thing>...
     mechanism=...because <how>...
     impact=...causing <impact on user/data/security/workflow>.
     fix_direction=<one sentence; not a rewrite>
     related_sites=path:line, path:line   (omit if none)
     root_cause_group=<short label for grouping in printed output>
     verifier_verdict=<holds|narrows|skipped-local>
```

### Dropped candidates

```
[D1] from=Fa2.1 reason=<guard-found|disproved-by-verifier|unsupported|superseded-by-F3>
     note=<one sentence — why this isn't a real finding>
```

Dropped candidates are preserved — they document the decision trail and support re-runs.

---

## `review.md` — Review phase

The rendered Markdown review printed to chat. **Not structured records.** Sections per `SKILL.md`'s "Output structure" — `# Custom Review — <target>`, `## Findings` (severity-banded), `## Open questions`, `## Coverage`.

The hard invariant: a finding appears in `review.md` only if it appears in `verification.md` as `[F1]`-shaped with `verifier_verdict` of `holds`, `narrows`, or `skipped-local`.

---

## ID prefix legend

| Prefix | Artifact | Meaning |
|---|---|---|
| `S0` | `scope.md` | Scope record (single) |
| `Src` | `model.md` (Sources) | Source of truth |
| `C` | `model.md` (Claims) | Falsifiable claim |
| `Sf` | `model.md` (Surfaces) | Changed semantic surface |
| `T` | `search.md` (Traces) | End-to-end trace |
| `H` | `search.md` (Hits) | Search hit |
| `A` | `search.md` (Audit) | Completeness audit entry |
| `Sb` | `search.md` (Siblings) | Sibling-path block |
| `Fa` | `falsification.md` | Falsification block per claim |
| `Ta` | `tests.md` | Test audit block |
| `F` | `verification.md` (Verified) | Verified finding |
| `D` | `verification.md` (Dropped) | Dropped candidate |
