# Review primitives

This file is the review's **detection spine**: five root primitives that every concrete check is an
instance of. To review, apply the roots a change touches to each changed *obligation* — a behavior,
contract, guard, or claim the change makes. The roots are the unit you hold in your head; the
instances under each are priming detail, not a checklist to tick.

A check is wrong-shaped if you've ticked it without naming the specific surface or site it applies to.

**The five roots:**

1. **Trace, don't skim** — follow each changed value / contract across the component boundary to its real read-site and its operator-observable effect; and the inverse, a returned value to wherever a caller drops it.
2. **Diff the siblings** — every changed obligation (a behavior, a guard, an authorization check, an error-branch, a default, a terminal-state) belongs to a set of places that must all honor it; the new or changed one is where it silently breaks.
3. **Probe the negative space** — the absent / empty / malformed / old / boot / fall-through / permissive case, and the fixtures and reasoning that quietly exclude it.
4. **Follow the async lifetime** — every event that should invalidate in-flight work, every teardown bound that must reach a completeness signal, every ordering assumption between concurrent tasks.
5. **Distrust the narrative** — read docs / comments / ADRs / plans / rules / claims as falsifiable assertions about the code, both directions (a false claim is a finding; a *true* claim describing broken behavior is **not** a pass). Covers the plan/issue the change implements (every obligation realized, to spec?), the governing docs the change ought to have updated but left stale, and the repo's own rule-docs the change must obey.

**How the workflow uses this file.** At step 2, note which roots the change touches (lookup below) and skim their **Failure signature** lines. At step 6, falsify each claim through the in-scope roots' instances. At step 9, before promoting a candidate, re-read the failure signatures of the roots in scope and ask whether the candidate is immune to each.

## Class-triggered lookup

Identify the change classes in scope, prime on the listed roots (and the named instances). Most diffs
touch 2–3 roots; reading all five on every review is wasted runtime.

| Change class | Roots (key instances) |
|---|---|
| New / changed semantic surface (type, enum, field, schema, status, route) | 1 (trace both directions; serialization; semantic-mismatch), 3 (cache keys) |
| New producer / writer / dispatch arm meant to affect current behavior | 1 (producer-realization + returned-value-discarded; dead-state) |
| Changed user workflow / command / action path | 2 (sibling parity), 1 (feature-unreachable), 3 (persistent-state) |
| Refactor or extraction | 2 (behavior + error-branch parity), 4 (mount-time side effects) |
| New code path mirroring an established sibling | 2 (behavior/guard parity), 1 (returned-value-discarded) |
| New early return / branch / guard | 3 (old-inputs-hit-new-branch; predicate truth-table) |
| Async / cancellation / sequencing / finalize-persist | 4 (async invalidation; teardown completeness), 1 (returned-value-discarded) |
| UI / persistent state / cache | 3 (persistent-state; cache keys) |
| Permission or auth change | 2 (authority parity), 3 (predicate truth-table) |
| Migration or schema | 3 (migrations vs existing data) |
| Wire format / serialization / persisted config | 1 (serialization), 2 (backward-compat), 3 (predicate truth-table) |
| Touched tests | cross-cutting (fixture blindness) |
| Docs / comments / runtime-model / ADRs / plan-docs in the diff | 5 (doc-vs-impl both directions; new-vs-reused; rule-as-policy) |
| Change implements/closes a plan or tracked issue, OR touches a surface a spec / ADR / rule-doc governs (even with no doc in the diff) | 5 (plan-completeness; doc-drift; rule-as-policy) |
| Defensive flags / accumulators / scratch state | 1 (dead-state) |
| Boolean predicate gating a destructive or wire-visible effect | 3 (predicate truth-table) |
| New operator-facing entry (keybinding, prompt-command, menu item, MCP tool, CLI subcommand, dispatch arm) | 1 (feature-unreachable / dispatch chain), 2 (authority parity) |
| UI → command → output edit chain (inline editor, form commit, request crafter) | 1 (feature-unreachable, step 3: assert the output carries the edit) |

## Cross-cutting: trust your evidence

These apply to **every** root, so they live here rather than under one:

- **Test-fixture blindness.** A green test proves nothing about a root if the fixture excludes the failure or bypasses the producer. (a) *Value-masking* — a fixture pre-assigning globally-unique / always-valid / non-colliding inputs hides a producer's real collision or malformed-input mode (e.g. globally-unique seq values mask a per-direction-seq collision). (b) *Producer-bypass* — a test that hand-builds the output struct and asserts on it exercises nothing the producer does; confirm at least one test drives the real producer fn (e.g. gutter tests build a `FindingGutterIndex` directly and never call `finding_gutter_index()`, so a status-fold bug ships green). A test that passes *while the bug is present* is itself a candidate, severity = the underlying defect.
- **Drop, don't hedge.** Unverified suspicions become Open Questions only when the uncertainty itself is high-risk; otherwise they are dropped. Never hedge a suspicion into a finding.
- **Don't bury the signal.** Cleanliness / style / naming observations do not compete with real findings; group by root cause and push weak items to Residual Risk.

---

## 1. Trace, don't skim

Do not treat the changed files as the universe of the review. Follow each changed value or contract to the site that actually reads it, and on to what the operator observes — and run the mirror check on values that flow *outward*.

**Failure signature — you skipped this root when:**
- The changed function looks reasonable; the bug is in a caller / serializer / export / admin path you never opened.
- The producer looks correct, but the actual read-site reads `Default::default()` / a fallback / a stale cache / an unrelated config — or there is no read-site at all.
- A returned value is dropped (`let _ = f()`, an unused `Ok(_)`, a success arm that ignores it).
- An operator-facing entry binds and the command emits, but the producer no-ops, targets a stale id, or its precondition is never realized.
- The impact names a user-visible artifact (modal, status line, redraw) but no render path was proven.

**Instances:**

- **Trace both directions.** For every changed type / enum / field / status / contract, search every CONSUMER (filters, exports, analytics, audit logs, admin views, tests are the usual misses) AND every PRODUCER (which code paths can emit this category?). *Example:* backend returns `archived_at` instead of `is_archived`; the page updates but CSV export still filters `is_archived` and leaks archived rows. A new edge-type is handled in the UI but the live API still emits the old type, so the view only works in seeded tests.
- **Producer-realization & its inverse.** For a new producer (writer / dispatch-arm / editor / setter / emitter / persisted record / config key), name the actual read-site and the source of truth *at that site*. A read-site that resolves to a default / unrelated config / dead branch — or no read-site — is the producer-dead class; promote immediately. *Inverse:* a returned value (a capture, result, status, handle, count) that a sibling caller or a contract persists, but a NEW caller drops. *Example:* an editor writes `config.toml` and `Ctrl+G` saves, but the engine command reads `AgentPermissionsConfig::default()` — the feature ships dead. A divert success arm drops the returned `ResponseCapture` its normal-send sibling's `build_result_flow` persists.
- **Serialization boundaries.** Renaming an internal symbol can silently change the on-the-wire form (JSON, DB column, CLI flag, env var, persisted config). *Example:* an internal enum variant is renamed → existing saved configs no longer load.
- **Semantic mismatch behind matching types.** Two structurally identical types (IDs of different entities, durations in different units, paths in different namespaces, timestamps in different zones) compile while the meaning changes. *Example:* a helper takes `workspaceId`; the caller passes `organizationId`; tests use the same fake id for both.
- **Dead / defensive state.** A flag / accumulator / scratch field with no observable read on the real control flow (or read only in an unreachable arm) is "looks load-bearing but isn't" — name every read site and trace reachability from a real entry point. Symmetric scan: a new dispatch arm / status / variant with no real producer is the read-but-not-written / dead-dispatch class.
- **Feature shipped but unreachable.** For every new operator-facing entry (keybinding, prompt-command, menu item, MCP tool, CLI subcommand, dispatch arm), trace **binding → command emitter → engine receiver → producing handler**, confirming each layer accepts the exact value the prior emits and the producer's precondition is realized. Then, for an edit chain, **assert the output artifact carries the operator's full edit** — the field NAME as well as its value, the toggled mode as well as the bytes. *Example:* a `d` keybinding emits `ProxyScopeRemove` against `scope_selected`, but nothing auto-selects on empty→non-empty, so `scope_selected` stays `None`. An inline-edit commit writes the field value but keeps the empty name, so `to_request()` never carries a keyboard-added header. (This dispatch chain is what satisfies `Render proof:` in `SKILL.md` § *Visibility-dependent findings*.)

**Search targets:** every occurrence of an old name and every consumer of a new shape; the real read-site and source-of-truth for every new producer, plus every NEW caller of a function whose return value a sibling persists; every cross-boundary serialization; every defensive field's read sites traced for reachability; every new operator-facing entry's integration site and each dispatch layer.

---

## 2. Diff the siblings

Every changed obligation belongs to a *set* of places that must all honor it. Validating the changed instance in isolation misses the silent asymmetry where one member does less.

**Failure signature — you skipped this root when:**
- You reviewed create but not edit; admin but not user; single but not bulk; one protocol lane but not its sibling.
- A new path mirrors an existing sibling but silently does *less* — omits a response-attach, picks a wrong per-input default, maps an error to the wrong terminal state.
- A new privileged arm omits the actor / authorization guard its sibling privileged arms carry.
- A limit / validation enforced in one implementation is dropped in its sibling.
- A fix repaired one site of a class but not its sibling sites.

**Instances:**

- **Behavior & guard parity.** For every NEW path that mirrors a sibling, enumerate what the sibling does after the shared step — attach a response, set a terminal state, persist a returned value, pick a per-input default, **and enforce the same validation / size-or-rate limit / authorization check** — and confirm the new path does each. Guards count, not just visible behavior. *Example:* an h2 header decoder doesn't enforce the head-size limit the HTTP/1 parser enforces, so h2 traffic bypasses a bound the sibling lane applies. A `resolve_dial_authority` defaults a portless authority to `:443` for ALL transports (wrong `:80` for the cleartext ones).
- **Error / failure-branch parity (and finding-vs-OQ).** When the change adds or alters one error/failure branch, find the sibling branch(es) for the same failure class and compare: one sets `persist_error`, the other doesn't; one maps `Aborted`, the other `Completed`; one advances a cursor, the other doesn't. Run this *before* deciding finding-vs-OQ — if the sibling proves the intended contract, the divergence is a finding; if the sibling shows it's deliberate, demote to an Open Question.
- **Authority parity.** (a) *Payload surfaces:* a NEW endpoint / tool / query returning the SAME sensitive payload an existing one gates must require AT LEAST the existing surface's permission group(s) — a single-group classification can't express a required conjunction (e.g. `FindingRead + FlowRead`). (b) *Dispatch arms:* a NEW privileged arm in a shared command / mutation dispatcher must carry the actor / authorization guard its sibling privileged arms carry; a missing actor-check is a privilege-escalation finding even when a separate catalog / allow-list (layer one) currently hides it — the sibling's guard exists precisely as that layer-two defense. Permission changes are also two-sided (who is newly allowed AND newly blocked), and UI gating ≠ server enforcement. *Example:* `finding.get_flow` returns the `Read`-gated `FlowDetail` but is classified `FindingRead`. Operator-only `JobCreateScanBackfill` / `Scanner*` arms omit the actor-check their `FindingClearReview` sibling has, reachable via a `command_as_agent` path.
- **Backward-compat / rollout (version siblings).** Old-producer/new-consumer AND new-producer/old-consumer must both work; old data, old clients, old configs, old persisted enums are the siblings of the new code. *Example:* the API stops emitting a field after the frontend updates; mobile still requires it.
- **Fix-site parity.** A fix is a change: when it repairs one site of a class, the other sites of that class are its siblings — confirm the fix reaches them. *Example:* a reload-error guard added to the project config layer but not the global layer leaves the global sibling broken.

**Search targets:** for every changed workflow, its parallel implementations; for every new path with a sibling, the sibling's full behavior + guards after the shared step; for every permission-touching change, the UI gate vs the server check, sibling payload surfaces, and sibling privileged dispatch arms; for every wire/contract change, both directions of partial deployment; for every fix, the other sites of the same class.

---

## 3. Probe the negative space

Most bugs hide in the rows nobody tests or reasons about: the absent, empty, malformed, old, fall-through, or permissive case — and the fixtures that exclude them.

**Failure signature — you skipped this root when:**
- A migration or new branch was evaluated only against ideal new data.
- A new early-return catches old valid inputs by accident.
- A predicate's permissive branch (everything absent / the parser failed / the fall-through) is untested.
- A fixture makes the regression impossible to fail (see cross-cutting fixture-blindness).

**Instances:**

- **Old inputs hitting a new branch.** For every new early-return / branch / guard, ask which old valid inputs now satisfy this condition by accident. *Example:* an early-return on `items.length === 0` to show an empty state also fires while `items` is briefly empty during loading → flashes "No results" and suppresses the spinner.
- **Persistent state through the next actions.** After this state is set, what does the user do next (navigate, refresh, change filter, submit, retry, select another item)? *Example:* a path search stores the selected result id; after a repo switch the stale id shows the previous repo's file.
- **Cache keys include every input.** Every input that influences the response (filters, permissions, locale, org, feature flags, sort) must be in the key. *Example:* the key includes `projectId` but not `includeArchived`, so toggling the archived view shows cached active-only results.
- **Migrations vs existing data.** Real rows have nulls, duplicates, old enum values, partial deployments. *Example:* a migration adds a non-null FK populated from "the latest event"; accounts with no events fail, though tests only used accounts with events.
- **Negative-space truth-table for boolean predicates.** A `fn(...) -> bool` gating a destructive / irreversible / wire-visible side-effect hides bugs in its permissive branch. (a) *Caller-local:* which return value unlocks the destructive op (sometimes `true`, sometimes `false`)? (b) *Function-local:* enumerate every path returning the permissive value — no relevant attribute present, attribute malformed (parse-error → default), multiple values where one was anticipated, fall-through at end, edge-case early-return — and ask whether the gated op is still safe for each. Write the one-line truth-table in `notes.md`. *Example:* `framing_carries_body` returns `false` when there's no `Content-Length > 0` AND no `Transfer-Encoding: chunked`; HTTP/1.0 close-delimited responses hit this path, and the caller then accepts a `200 OK + body` → `204 No Content` patch — a wire-desync. Coverage tested CL=0/CL>0/TE=chunked but never "no framing headers at all".

**Search targets:** for every new branch, the old inputs that now hit it; for every new persistent state, the next user action; for every cache key, every input affecting the response; for every migration, the production rows that break its assumptions; for every destructive-gating predicate, the truth-table row that returns the permissive value.

---

## 4. Follow the async lifetime

Reason about cancellation, teardown, and ordering between concurrent tasks — not just the replacement and happy paths.

**Failure signature — you skipped this root when:**
- New requests work, but old requests aren't cancelled on a state change.
- A finalize reads one of several teardown bounds, and another bound tears down silently.
- A dependent command fires before a prior command's async side-effect has landed.
- A child component mounts and fetches earlier than the parent gated.

**Instances:**

- **Async invalidation, not just replacement.** Every event that resets state or changes identity (clear, navigate, blur, filter change, identity switch, cancel) must invalidate in-flight work. *Example:* clearing a filter resets results, but the earlier request resolves and repopulates stale results because clearing didn't advance the request token. (A cancel that should invalidate a pending progress write but doesn't — letting a stale write resurrect a non-terminal state over a `Cancelled` terminal — is this class.)
- **Mount-time side effects after extraction.** When data-fetching moves into a child, the `enabled` / `skip` guard that suppressed querying may now be absent, so the child mounts and fetches with `id === undefined`. *Example:* the parent rendered the details query only after the user selected an id; the new child queries immediately → 400 loop or broad fallback.
- **Cross-async-task teardown completeness.** When a finalize / persist reads a completeness signal (`truncated`, a terminal state, a byte count) written by tasks bounded by join / drain timeouts, cancellation, or `select!` arms, EVERY teardown path must reach that signal. *Example:* the finalize reads only the drain timeout to set `s2c_truncated`; the per-task join timeout is discarded (`let _ = timeout(...)`), so a blob clipped by the join timeout persists as `truncated == false` — a silent truncation reported as complete.

**Search targets:** every state-reset / identity-change event and whether it cancels in-flight work; the `enabled`/`skip` guard that existed before a data-fetch extraction; for every finalize/persist reading a completeness signal, every teardown path of the producing tasks.

---

## 5. Distrust the narrative

Read every doc, comment, ADR, plan, and PR-body claim as a falsifiable assertion about the code. The promotion gate is **"is the claim currently false?"** — *not* "is the headline bug reachable through it?"

**Failure signature — you skipped this root when:**
- You noticed a comment lying but dropped it because "the headline bug isn't reachable through this comment."
- You dropped a real behavioral bug as `claim-currently-true` because the comment describing the broken behavior was literally accurate.
- You treated an ADR or plan-doc as inert narrative rather than a claim to falsify.
- You reviewed only the diff and never located the plan / tracked issue the change implements, so you never checked whether every obligation shipped and matches spec.
- The change altered behavior a spec / ADR / runtime-model / comment governs, but you let the now-stale doc stand because it wasn't *literally* contradicted.
- You read the repo's rule-docs (`CLAUDE.md` / `AGENTS.md` / `CONTRIBUTING`) for context but never falsified the diff against the rules they impose.

**Gate:** a claim currently false → finding (floor Low, ceiling Medium per the severity rubric; High only if a documented future consumer in the same PR will be misled). A claim currently true → drop *as a claim-vs-reality finding* — but apply the carve-out below first. The audience for these findings is explicit: *"maintainers will act on a false model."* A governing doc the change leaves stale (now contradicted OR now silently incomplete about the surface it owns) is the same class — grade it by impact, not by whether the staleness is literal: a trivially-minor inaccuracy is a Low finding, not a drop.

**Instances:**

- **Doc-vs-impl-lies (both directions).** A doc and the code it governs disagree; falsify each bullet against the enum / struct / function it describes. *Doc ahead of code:* a comment / docstring / runtime-model table / ADR / plan-doc / PR-body bullet claims behavior the code beside it doesn't implement. *Code ahead of doc (drift):* the change alters behavior a doc owns but leaves that doc unchanged, so the doc is now stale — contradicted, or silently incomplete about a surface it enumerates/governs. Drift counts for docs that are a source of truth for the changed surface (spec, ADR, runtime-model, the comment beside the code), not incidental prose that merely mentions the concept; grade staleness by impact (trivially-minor → Low, not a drop). *Example:* a runtime-model table still reads `NotImplemented` for arms wired in this change (doc ahead); a new enum variant ships but the spec table enumerating the variants isn't extended (drift).
- **Plan / spec completeness.** When the change implements a plan, spec, or tracked issue, treat that document as a checklist: every obligation needs implementing code, and each implementation must match what the obligation specifies (not merely share its name). A missing or off-spec obligation is a finding **when the change is meant to close/complete that plan/issue** — signalled by `closes #N` / "implements <plan>" or framing that presents the PR as finishing the work; when the PR is explicitly partial or one of a stack, unmet obligations are Open Questions / coverage, not findings. Prove the gap: the obligation names a surface, and a search across diff and repo finds no realizing code. *Example:* an issue lists three config keys to add; the diff wires two and says "closes #N" — the missing third is a finding.
- **New-vs-reused member cross-check.** When a doc / comment / plan lists members as "new / added / `<feature>`-specific" vs "reused / existing / shared", verify each against its real definition. *Example:* a doc lists `Status` among "finding-specific additions" but `SearchField::Status` is the reused HTTP-status variant.
- **Rule-as-policy (governing docs are a contract the diff must obey).** ADRs, specs, and the repo's own rule-docs (`CLAUDE.md` / `AGENTS.md` / `GEMINI.md` / `CONTRIBUTING`) impose rules the change must honor; a violation is a finding even when the code runs. Falsify the diff *against* these rules — don't read them only for priming. A rule can mandate the OPPOSITE of your instinct: a pre-stability ADR may say to reject old on-disk data and delete compat code rather than extend it, so a change that ADDS a compat shim (a `serde(alias)`, a fallback decoder, a version-coercion) where the ADR says reject is itself a violation, not a safe backward-compat win. *Example:* a rule-doc requires every error-propagation to carry a `.context()`; a new `?` site without one violates a stated repo rule.
- **Claim-true-but-behavior-wrong carve-out.** This gate scores the *comment*, not the behavior it describes. A literally-accurate comment does NOT clear a candidate when the accurately-described **behavior** is itself the defect — route those back through the behavioral roots (1–4) and promote on the behavior; do not record `dropped reason=claim-currently-true`. *Example:* a `cycle_send_mode` comment says "re-cycle to refresh" (true), but the behavior it accurately describes clones a stale authority after an edit.

**Search targets:** every touched code path's adjacent comments/docstrings; `runtime-model.md`, ADRs, READMEs, in-tree spec files, and plan/roadmap docs — landed in the diff, OR linked from the PR/issue, OR found by a concept-term search across `docs/plans`, `docs/specs`, `SESSION.md`, root `*.md` — that mention or govern the touched concept, each checked both directions (doc-ahead and code-ahead/stale); the plan/issue the change closes, walked as a completeness checklist; every "new vs reused" grouping; every new code path and backward-compat shim weighed against the governing ADR's policy and the repo rule-docs.
