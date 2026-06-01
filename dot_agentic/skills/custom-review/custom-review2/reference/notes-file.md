# Notes file — `tmp/custom-review-<ts>/notes.md`

**Mandatory** review artifact. Carries the enforcement that v1 spread across seven files: surface enumeration, falsifiable claims, per-claim falsifications + sub-checks, the candidate ledger (anti-trigger-shy), coverage transparency, and the preflight result.

Read this file before workflow step 3 (enumerate surfaces). The structure below is required — the reviewer fills it in as the workflow progresses.

The meta-fixer / operator adjudicates only `review.md`. `notes.md` is reviewer-internal. It is not credit-bearing for benchmarking; its purpose is to force the reviewer through the workflow without skipping.

## Format

```markdown
# Custom Review notes — <target>

target: <pr#|sha|branch-name|HEAD|paths|snippet>
head_oid: <oid if pr|branch|commit>

## Surfaces

- S1 <kind> <old_form|N/A> → <new_form|N/A>
    grep_terms: <list including old form, new form, every serialized alias — camelCase ↔ snake_case ↔ kebab-case, route slugs, DB columns>
    claim_refs: C1, C3
- S2 ...

## Claims

### C1 — <one-line falsifiable statement: "The code now promises X. X is false if Y.">

  tier: <observable-wrong-behavior | silent-state-divergence | contract-violation-not-yet-visible | procedural-doc-drift | comment-precision | N/A>
  surfaces: S1, S2
  producer-realization: producer=<file:line>; produced=<value>; intended-consumer=<concept>; actual-read-site=<TBD|file:line>; source-of-truth-at-read=<TBD|concrete>; observable-effect=<one-line>
    (omit the producer-realization line entirely if this claim is not about a new producer)
  falsifications:
    - <one-line attempt> — <disproved|reachable-defect|open-question> reason=<one line>
    - <one-line attempt> — ...
    - <one-line attempt> — ...
  sub-checks:
    backward_compat:    <finding|checked-no-issue|N/A reason=...>
    failure_parity:     <finding|checked-no-issue|N/A reason=...>
    async_invalidation: <finding|checked-no-issue|N/A reason=...>
    deletion_orphans:   <finding|checked-no-issue|N/A reason=...>

### C2 — ...

## Candidates

(One Kn line per reachable-defect / open-question / sub-check finding / dead producer-realization / ADR-drift / test-derived defect / dead-state observation. Every line ends with a status. Drop reasons are substantive.)

- K1 <class> from C1.falsifications#2  <path:line> — <condition> → <wrong behavior>; status=<verified-finding-Fn | open-question-OQn | dropped reason=<one-line>>
- K2 <class> from C3.sub-checks.async_invalidation  <path:line> — ...; status=...
- K3 <class> from C1.producer-realization  <path:line> — actual-read-site reads Default::default(); status=verified-finding-F2
- ...

## Coverage

- inspected: <paths or directory groups>
- not checked: <paths + reason>
- commands run: <git diff / rg / cargo / npm / etc.>
- subagents used: <completeness-audit returned N missing surfaces; adversarial-verifier holds/disproved/narrows/unsupported per finding>  (omit if no subagents ran)

## Preflight

preflight: <passed | returned-to=<step> reason=<one-line>>
```

## Field rules

### `## Surfaces`

- **Every changed semantic surface gets a line.** Deletions count. Be exhaustive — this is what the step-4 completeness-audit subagent checks against.
- `grep_terms` should be narrow enough that step 7's classification doesn't recreate v1's process tax, but broad enough to catch sibling producers (include serialized aliases).

### `## Claims`

- **No claim cap.** If you have >8 claims, group by root-cause concept; the group's falsifications must still cover each member's distinct surface.
- `tier:` anchors severity at step 9. Refactor-parity claims may start at `N/A` but must escalate to a real tier the moment parity breaks.
- `producer-realization:` is mandatory for any claim about a new producer. Start with `TBD` placeholders and finalize after step 7 search; a finalized row that reveals the consumer reads a default / unrelated config / stale cache / dead branch — or no consumer at all — is the producer-dead class. Promote a `Kn` immediately.
- **≥3 falsifications per claim** with result tags. Small-mode (per SKILL.md *Risk-aware small mode*) relaxes this to ≥1 per claim plus two sub-checks (`failure_parity` + `backward_compat`).
- **All four sub-checks per claim** must be addressed in normal mode: `finding | checked-no-issue | N/A reason=...`. No silent skips.

### `## Candidates`

- **Status is required.** Every candidate must end as `verified-finding-Fn`, `open-question-OQn`, or `dropped reason=<one-line>`. The verified-finding ID matches the rendered review's finding ID; the open-question ID matches the rendered Open Question.
- **Dropped candidates require a substantive one-line reason.** Examples: `guard-found at foo.rs:42`, `disproved-by-adversarial-verification cited bar.rs:88`, `no-render-path-proof`, `claim-currently-true`, `not-yet — claim ships dead but no downstream consumer yet`. Not `nit` or `oos`.
- **`<class>` token** — single token, makes the ledger searchable. One of: `producer-realization`, `producer-dead`, `visibility`, `claim-vs-reality`, `doc-lie`, `dead-state`, `sibling`, `backward-compat`, `async-invalidation`, `test-fixture`, `adr-drift`, `other`.
- **The candidate's `from` reference** names where it originated: `from C1.falsifications#2`, `from C3.sub-checks.async_invalidation`, `from C1.producer-realization`, `from step-8.test-fixture`, `from step-2.adr-drift`. This makes return loops auditable.

### `## Preflight`

- Final state must be `preflight: passed`. The `returned-to=<step>` form is transient — it appears while a return loop is active. `review.md` is not rendered while `returned-to=...` is open.

## Length

There is no hard length cap. The notes file scales with the diff. A small/clean PR's notes may be under 40 lines; a 20-file PR's notes typically run 200–400 lines. Verbose claim blocks beat skipped sub-checks.

## Falsifications counter (mechanical, not prose)

The reviewer does NOT write the falsifications count by hand. It is counted from the `falsifications:` lines under each `## Claims` block and their linked `## Candidates` statuses; `output-format.md`'s Coverage section template prescribes the rendering.
